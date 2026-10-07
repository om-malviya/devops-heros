#!/usr/bin/env bash
# Kubernetes Basics tutorial (kubernetes.io/docs/tutorials/kubernetes-basics/) as a script.
# Modules: 1 create cluster, 2 deploy app, 3 explore app, 4 expose publicly, 5 scale, 6 update.
#
# Usage:
#   ./commands.sh                 run all six modules with the imperative kubectl commands from the tutorial
#   USE_YAML=1 ./commands.sh      use deployment.yaml / service.yaml instead of kubectl create/expose
#   NAMESPACE=s09 ./commands.sh   run in a namespace (created if missing); default is "default"
#   CLEANUP=1 ./commands.sh       delete the deployment/service at the end (cluster is left running)
#
# Works with minikube (the documented install path) and with any other cluster kubectl already
# points at (k3s via Colima, kind, Docker Desktop). When minikube is not installed or not the
# current context, the app is reached with "kubectl port-forward" instead of "minikube service".
set -euo pipefail

DEPLOY=kubernetes-bootcamp
IMG_V1=gcr.io/google-samples/kubernetes-bootcamp:v1
IMG_V2=jocatalin/kubernetes-bootcamp:v2
IMG_BAD=gcr.io/google-samples/kubernetes-bootcamp:v10
NS="${NAMESPACE:-default}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PF_PORT=18080
PF_PID=""

banner() { printf '\n==================== %s ====================\n' "$*"; }
run()    { printf '\n$ %s\n' "$*"; "$@"; }
k()      { kubectl -n "$NS" "$@"; }

for bin in kubectl curl; do
  command -v "$bin" >/dev/null || { echo "missing: $bin (brew install $bin)"; exit 1; }
done

use_minikube=0
if command -v minikube >/dev/null && [[ "$(kubectl config current-context 2>/dev/null)" == "minikube" ]]; then
  use_minikube=1
fi

# app_url: prints a URL that reaches the Service from this machine.
app_url() {
  if [[ $use_minikube == 1 ]]; then
    minikube service "$DEPLOY" -n "$NS" --url
  else
    if [[ -z "$PF_PID" ]] || ! kill -0 "$PF_PID" 2>/dev/null; then
      kubectl -n "$NS" port-forward "service/$DEPLOY" "$PF_PORT:8080" >/dev/null 2>&1 &
      PF_PID=$!
      sleep 2
    fi
    echo "http://localhost:$PF_PORT"
  fi
}
stop_pf() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null || true; PF_PID=""; }
trap stop_pf EXIT

banner "Module 1: create a cluster"
if [[ $use_minikube == 1 ]]; then
  if ! minikube status --format '{{.Host}}' 2>/dev/null | grep -q Running; then
    run minikube start --driver=docker
  fi
  run minikube status
else
  echo "minikube not in use; using current kubectl context: $(kubectl config current-context)"
fi
run kubectl version
run kubectl cluster-info
run kubectl get nodes -o wide
kubectl get namespace "$NS" >/dev/null 2>&1 || run kubectl create namespace "$NS"

banner "Module 2: deploy an app"
if [[ "${USE_YAML:-0}" == "1" ]]; then
  run k apply -f "$HERE/deployment.yaml"
else
  k get deployment "$DEPLOY" >/dev/null 2>&1 || run k create deployment "$DEPLOY" --image="$IMG_V1"
fi
run k rollout status deployment/"$DEPLOY" --timeout=180s
run k get deployments
run k get events --sort-by=.metadata.creationTimestamp | tail -n 6
run kubectl config view --minify

banner "Module 3: explore the app"
POD="$(k get pods -l app="$DEPLOY" -o jsonpath='{.items[0].metadata.name}')"
echo "Pod name: $POD"
run k get pods -o wide
run k describe pod "$POD"
run k logs "$POD"
run k exec "$POD" -- env
run k exec "$POD" -- cat server.js
run k exec "$POD" -- curl -s localhost:8080

banner "Module 4: expose the app publicly"
if [[ "${USE_YAML:-0}" == "1" ]]; then
  run k apply -f "$HERE/service.yaml"
else
  k get service "$DEPLOY" >/dev/null 2>&1 || run k expose deployment/"$DEPLOY" --type=NodePort --port 8080
fi
run k get services
run k describe service "$DEPLOY"
NODE_PORT="$(k get service "$DEPLOY" -o go-template='{{(index .spec.ports 0).nodePort}}')"
echo "NODE_PORT=$NODE_PORT"
sleep 2   # give kube-proxy a moment to program the NodePort
URL="$(app_url)"
echo "URL=$URL"
run curl -s "$URL"
echo "Same service, reached from inside the cluster by DNS name:"
run k run client --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- "http://$DEPLOY:8080"
run k get pods -l app="$DEPLOY"
run k label pod "$POD" version=v1 --overwrite
run k describe pod "$POD" | grep -A3 '^Labels'
run k get pods -l version=v1

banner "Module 5: scale the app"
run k scale deployment/"$DEPLOY" --replicas=4
run k rollout status deployment/"$DEPLOY" --timeout=180s
run k get deployments
run k get rs
run k get pods -o wide
run k describe service "$DEPLOY" | grep Endpoints
echo "Six requests - the service load-balances across pods:"
stop_pf; URL="$(app_url)"   # restart the port-forward so it is not pinned to one pod
for i in 1 2 3 4 5 6; do curl -s "$URL"; done
run k scale deployment/"$DEPLOY" --replicas=2
run k rollout status deployment/"$DEPLOY" --timeout=180s
run k get pods -o wide

banner "Module 6: update the app (rolling update) and roll back"
run k set image deployment/"$DEPLOY" "$DEPLOY"="$IMG_V2"
run k rollout status deployment/"$DEPLOY" --timeout=180s
run k get pods
stop_pf; URL="$(app_url)"
run curl -s "$URL"
run k describe deployment "$DEPLOY" | grep -i image
run k rollout history deployment/"$DEPLOY"
echo "Now a bad image (tag v10 does not exist) to see ImagePullBackOff:"
run k set image deployment/"$DEPLOY" "$DEPLOY"="$IMG_BAD"
k rollout status deployment/"$DEPLOY" --timeout=60s || true
run k get pods
run k get rs
run k rollout history deployment/"$DEPLOY"
run k rollout undo deployment/"$DEPLOY"
run k rollout status deployment/"$DEPLOY" --timeout=180s
run k get pods
run k describe deployment "$DEPLOY" | grep -i image
run k rollout history deployment/"$DEPLOY"

if [[ "${CLEANUP:-0}" == "1" ]]; then
  banner "Cleanup"
  run k delete service "$DEPLOY"
  run k delete deployment "$DEPLOY"
  [[ "$NS" != "default" ]] && run kubectl delete namespace "$NS"
  [[ $use_minikube == 1 ]] && echo "Cluster left running. To remove it: minikube stop && minikube delete"
fi

banner "Done"
