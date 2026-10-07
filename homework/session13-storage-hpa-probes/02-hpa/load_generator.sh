#!/usr/bin/env bash
# load_generator.sh - start/stop the HPA load generator for Session 13 (adapted from the course script).
# The course version ran curl loops on the laptop through a port-forward; this version runs the loop
# INSIDE the cluster (busybox Deployment) so it works on any arch, needs no local port and generates
# enough load to push cpu-app above its 50% CPU target.
#
# Usage:
#   ./load_generator.sh            # start 3 load pods
#   ./load_generator.sh 6          # start 6 load pods (more load)
#   ./load_generator.sh --stop     # remove the load generator
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS=s13

if [[ "${1:-}" == "--stop" ]]; then
  echo "[load] stopping load generator"
  kubectl delete -f "${DIR}/load-generator.yaml" --ignore-not-found=true
  echo "[load] watch the scale-down with:  kubectl get hpa -n ${NS} -w"
  exit 0
fi

REPLICAS="${1:-3}"
echo "=================================================="
echo "      KUBERNETES HPA TRAFFIC LOAD GENERATOR       "
echo "=================================================="
echo "[load] target: http://cpu-app.${NS}.svc.cluster.local/  (replicas: ${REPLICAS})"
kubectl apply -f "${DIR}/load-generator.yaml"
kubectl scale -n "$NS" deployment/load-generator --replicas="$REPLICAS"
kubectl rollout status -n "$NS" deployment/load-generator --timeout=120s
echo "[load] traffic active. In other terminals run:"
echo "         kubectl get hpa -n ${NS} -w"
echo "         kubectl get pods -n ${NS} -l app=cpu-app -w"
echo "         kubectl top pods -n ${NS}"
echo "[load] stop with:  $0 --stop"
