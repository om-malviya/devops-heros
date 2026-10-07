#!/usr/bin/env bash
# ==============================================================================
# rollback-demo.sh - complete Helm rollback workflow for the webapp chart
#
#   install (rev 1)  ->  upgrade (rev 2: nginx:1.27-alpine, 2 replicas)  ->  verify
#   -> upgrade again (rev 3: 3 replicas, new message)  ->  verify
#   -> rollback to revision 2 (rev 4)  ->  verify
#
# `helm history` is printed after every step.
# Usage: ./rollback-demo.sh            run the workflow
#        ./rollback-demo.sh --cleanup  uninstall the release and delete the namespace
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${NS:-s15}"
RELEASE="${RELEASE:-webapp}"
CHART="$SCRIPT_DIR/webapp"

step()    { echo; echo "################################################################"; echo "# $1"; echo "################################################################"; }
run()     { echo; echo "\$ $*"; "$@"; }
history() { run helm history "$RELEASE" -n "$NS"; }

verify() {
  # $1 = expected replicas, $2 = expected image tag, $3 = expected message
  step "VERIFY: expecting replicas=$1 image=nginx:$2 message=\"$3\""
  run kubectl rollout status deployment/"$RELEASE" -n "$NS" --timeout=120s
  run kubectl get deployment "$RELEASE" -n "$NS" -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image'
  run kubectl get pods -n "$NS" -l app.kubernetes.io/instance="$RELEASE"
  run helm get values "$RELEASE" -n "$NS"
  echo
  echo "\$ kubectl get configmap $RELEASE -n $NS -o jsonpath='{.data.MESSAGE}'"
  ACTUAL_MSG=$(kubectl get configmap "$RELEASE" -n "$NS" -o jsonpath='{.data.MESSAGE}')
  echo "$ACTUAL_MSG"
  ACTUAL_REPLICAS=$(kubectl get deployment "$RELEASE" -n "$NS" -o jsonpath='{.spec.replicas}')
  ACTUAL_IMAGE=$(kubectl get deployment "$RELEASE" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')
  if [[ "$ACTUAL_REPLICAS" == "$1" && "$ACTUAL_IMAGE" == "nginx:$2" && "$ACTUAL_MSG" == "$3" ]]; then
    echo "VERIFY OK: replicas=$ACTUAL_REPLICAS image=$ACTUAL_IMAGE message=\"$ACTUAL_MSG\""
  else
    echo "VERIFY FAILED: replicas=$ACTUAL_REPLICAS image=$ACTUAL_IMAGE message=\"$ACTUAL_MSG\"" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--cleanup" ]]; then
  step "CLEANUP"
  run helm uninstall "$RELEASE" -n "$NS" || true
  run kubectl delete namespace "$NS" --ignore-not-found
  exit 0
fi

step "0. Lint and render the chart (no cluster needed)"
run helm lint "$CHART"
helm template "$RELEASE" "$CHART" -n "$NS" > /dev/null && echo "helm template: OK"

step "1. INSTALL (revision 1: nginx:alpine, 1 replica, default message)"
run helm install "$RELEASE" "$CHART" -n "$NS" --create-namespace --wait --timeout 120s
history
verify 1 alpine "Hello from webapp v1"

step "2. UPGRADE (revision 2: image.tag=1.27-alpine, replicaCount=2)"
run helm upgrade "$RELEASE" "$CHART" -n "$NS" --set image.tag=1.27-alpine --set replicaCount=2 --wait --timeout 120s
history
verify 2 1.27-alpine "Hello from webapp v1"

step "3. UPGRADE AGAIN (revision 3: replicaCount=3, new message) - note --reuse-values keeps the 1.27-alpine tag"
run helm upgrade "$RELEASE" "$CHART" -n "$NS" --reuse-values --set replicaCount=3 --set message="Hello from webapp v3" --wait --timeout 120s
history
verify 3 1.27-alpine "Hello from webapp v3"

step "4. ROLLBACK to revision 2 (creates revision 4)"
run helm rollback "$RELEASE" 2 -n "$NS" --wait --timeout 120s
history
verify 2 1.27-alpine "Hello from webapp v1"

step "DONE - final state"
run helm list -n "$NS"
run helm status "$RELEASE" -n "$NS"
echo
echo "Clean up with: $0 --cleanup"
