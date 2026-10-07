#!/usr/bin/env bash
# ==============================================================================
# Script : triage.sh
# Purpose: Quick health report for one namespace (adapted from the course's
#          scenarios/triage_all.sh, which only deployed the broken workloads).
# Usage  : ./triage.sh [namespace] [--apply-all | --fix-all | --clean]
#            ./triage.sh                -> report for namespace s14
#            ./triage.sh s14 --apply-all -> apply every */broken.yaml, then report
#            ./triage.sh s14 --fix-all   -> apply every */fixed.yaml, then report
#            ./triage.sh s14 --clean     -> delete everything from */fixed.yaml and */broken.yaml
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${1:-s14}"
ACTION="${2:-}"

line() { printf '%s\n' "=================================================================="; }
section() { echo; line; echo "  $1"; line; }

if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
  echo "Namespace '$NS' does not exist. Creating it..."
  kubectl create namespace "$NS"
fi

case "$ACTION" in
  --apply-all)
    section "Deploying all broken scenarios into namespace $NS"
    for f in "$SCRIPT_DIR"/*/broken.yaml; do
      echo "--> $f"
      kubectl apply -n "$NS" -f "$f"
    done
    echo "Sleeping 20s so the states can settle..."
    sleep 20
    ;;
  --fix-all)
    section "Applying all fixed manifests into namespace $NS"
    for f in "$SCRIPT_DIR"/*/fixed.yaml; do
      echo "--> $f"
      # Pods are mostly immutable (env, args, volumes, resources, nodeSelector):
      # if apply is rejected, delete + recreate the objects in the file instead.
      kubectl apply -n "$NS" -f "$f" || {
        echo "    apply rejected (immutable Pod field) -> kubectl replace --force"
        kubectl replace --force -n "$NS" -f "$f"
      }
    done
    echo "Sleeping 20s so the states can settle..."
    sleep 20
    ;;
  --clean)
    section "Deleting all scenario resources from namespace $NS"
    for f in "$SCRIPT_DIR"/*/fixed.yaml "$SCRIPT_DIR"/*/broken.yaml; do
      kubectl delete -n "$NS" -f "$f" --ignore-not-found >/dev/null 2>&1 || true
    done
    echo "done"
    exit 0
    ;;
  "") ;;
  *) echo "unknown option: $ACTION" >&2; exit 2 ;;
esac

section "TRIAGE REPORT  namespace=$NS  $(date '+%Y-%m-%d %H:%M:%S')"

section "1. Pods that are not Running/Succeeded"
kubectl get pods -n "$NS" --field-selector 'status.phase!=Running,status.phase!=Succeeded' 2>/dev/null \
  || echo "(none)"

section "2. Container waiting reasons (CrashLoopBackOff, ImagePullBackOff, ...)"
kubectl get pods -n "$NS" -o custom-columns=\
'NAME:.metadata.name,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,WAITING:.status.containerStatuses[*].state.waiting.reason,LAST_EXIT:.status.containerStatuses[*].lastState.terminated.exitCode' \
  | awk 'NR==1 || $4 != "<none>" || $3 ~ /[1-9]/'

section "3. Services with no endpoints"
kubectl get endpoints -n "$NS" -o custom-columns='SERVICE:.metadata.name,ENDPOINTS:.subsets[*].addresses[*].ip' 2>/dev/null \
  | awk 'NR==1 || $2 == "<none>"'

section "4. PersistentVolumeClaims not Bound"
kubectl get pvc -n "$NS" 2>/dev/null | awk 'NR==1 || $2 != "Bound"' || echo "(none)"

section "5. NetworkPolicies in the namespace"
kubectl get networkpolicy -n "$NS" 2>/dev/null || echo "(none)"

section "6. Last 20 Warning events"
kubectl get events -n "$NS" --field-selector type=Warning --sort-by=.lastTimestamp 2>/dev/null | tail -n 20

section "7. Node status"
kubectl get nodes -o wide
kubectl top nodes 2>/dev/null || echo "(kubectl top: Metrics API not available)"

section "8. CoreDNS"
kubectl get pods -n kube-system -l k8s-app=kube-dns

echo
line
echo "Next step for anything listed above: kubectl describe pod <name> -n $NS  ->  Events"
line
