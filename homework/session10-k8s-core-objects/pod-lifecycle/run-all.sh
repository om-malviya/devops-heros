#!/usr/bin/env bash
# Applies every lifecycle example in order and prints the Pod status after a
# short wait so the interesting state has time to appear. Does not use -w so
# the script terminates on its own. Run cleanup.sh afterwards.
set -uo pipefail
cd "$(dirname "$0")"
NS=s10

kubectl apply -f ../namespace.yaml >/dev/null

show() {
  local pod=$1
  echo "--- kubectl -n $NS get pod $pod"
  kubectl -n "$NS" get pod "$pod"
  echo "--- container state"
  kubectl -n "$NS" get pod "$pod" -o jsonpath='{range .status.containerStatuses[*]}{.name}{" => "}{.state}{"\n"}{end}'
  echo "--- last events"
  kubectl -n "$NS" get events --field-selector "involvedObject.name=$pod" \
    --sort-by=.lastTimestamp -o custom-columns=REASON:.reason,MESSAGE:.message --no-headers | tail -n 6
  echo
}

run() {
  local file=$1 pod=$2 wait=$3
  echo "=================================================================="
  echo "== $file   (waiting ${wait}s)"
  echo "=================================================================="
  kubectl apply -f "$file"
  sleep "$wait"
  show "$pod"
}

run 01-running.yaml           lifecycle-running          10
run 02-pending.yaml           lifecycle-pending          5
run 03-succeeded.yaml         lifecycle-succeeded        15
run 04-failed.yaml            lifecycle-failed           15
run 05-crashloopbackoff.yaml  lifecycle-crashloop        45
run 06-imagepullbackoff.yaml  lifecycle-image-error      30

echo "== 07-readiness.yaml: status at 3s, then again at 20s"
kubectl apply -f 07-readiness.yaml; sleep 3;  kubectl -n $NS get pod lifecycle-readiness
sleep 17; kubectl -n $NS get pod lifecycle-readiness; echo

echo "== 08-liveness.yaml: RESTARTS should be >= 1 after ~45s"
kubectl apply -f 08-liveness.yaml; sleep 45; show lifecycle-liveness

echo "== 09-startup.yaml: 0/1 Running for ~30s, then 1/1 with 0 restarts"
kubectl apply -f 09-startup.yaml; sleep 10; kubectl -n $NS get pod lifecycle-startup
sleep 30; kubectl -n $NS get pod lifecycle-startup; echo

echo "== 10-init-container.yaml: Init:0/1 then Running"
kubectl apply -f 10-init-container.yaml; sleep 3; kubectl -n $NS get pod lifecycle-init
sleep 15; kubectl -n $NS get pod lifecycle-init
kubectl -n $NS logs lifecycle-init -c setup; echo

run 11-multi-container.yaml   lifecycle-multi-container  15
kubectl -n $NS logs lifecycle-multi-container -c sidecar | tail -n 2; echo

echo "== 12-termination.yaml: delete and time the graceful shutdown"
kubectl apply -f 12-termination.yaml
kubectl -n $NS wait --for=condition=Ready pod/lifecycle-termination --timeout=60s
kubectl -n $NS logs -f lifecycle-termination &
LOGPID=$!
sleep 2
START=$(date +%s)
kubectl -n $NS delete pod lifecycle-termination
END=$(date +%s)
wait $LOGPID 2>/dev/null || true
echo "Pod deletion took $((END-START))s (expected ~15s: 5s preStop + 10s SIGTERM handler)"
echo
echo "== Final state of all lab pods"
kubectl -n $NS get pods -l lab=pod-lifecycle
