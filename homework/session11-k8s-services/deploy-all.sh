#!/usr/bin/env bash
# Deploy every Service example of session 11 into namespace s11 and print
# the resulting Services and Endpoints.
set -euo pipefail
cd "$(dirname "$0")"
NS=s11

kubectl apply -f namespace.yaml
kubectl apply -f client-pod.yaml
for d in 01-clusterip 02-nodeport 03-loadbalancer 04-externalname 05-headless; do
  echo "== $d"
  kubectl apply -f "$d/"
done

echo "== waiting for workloads"
kubectl -n $NS rollout status deployment/web-clusterip --timeout=120s
kubectl -n $NS rollout status deployment/web-nodeport --timeout=120s
kubectl -n $NS rollout status deployment/web-loadbalancer --timeout=120s
kubectl -n $NS rollout status statefulset/web --timeout=180s
kubectl -n $NS wait --for=condition=Ready pod/client --timeout=60s

echo "== services and endpoints"
kubectl -n $NS get svc,endpoints -o wide
echo
echo "== quick connectivity check from the client pod"
kubectl -n $NS exec client -- sh -c '
  echo "clusterip   : $(wget -qO- http://web-clusterip)"
  echo "nodeport    : $(wget -qO- http://web-nodeport)"
  echo "loadbalancer: $(wget -qO- http://web-loadbalancer:8081)"
  echo "headless    : $(wget -qO- http://web-0.web)"
  echo "externalname: $(nslookup external-site 2>/dev/null | grep -i -m1 "canonical\|example.com" || echo "(no egress DNS)")"
'
