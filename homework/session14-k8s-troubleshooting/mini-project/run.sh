#!/usr/bin/env bash
# Walks through the mini project: deploy -> observe -> break -> investigate -> fix -> verify.
# Prints every command before running it so the output can be pasted into the README.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
NS=s14

run() { echo; echo "\$ $*"; "$@" || true; }
step() { echo; echo "==================== $1 ===================="; }

step "1. Deploy"
run kubectl apply -f ../namespace.yaml
run kubectl apply -f deployment.yaml -f service.yaml -f client-pod.yaml
run kubectl rollout status deployment/troubleshooting-app -n $NS --timeout=120s
run kubectl wait pod/client -n $NS --for=condition=Ready --timeout=120s

step "2. Observe the application"
run kubectl get pods -n $NS -o wide
POD=$(kubectl get pod -n $NS -l app=troubleshooting-app -o jsonpath='{.items[0].metadata.name}')
run kubectl describe pod "$POD" -n $NS
run kubectl logs "$POD" -n $NS --tail=5
run kubectl exec "$POD" -n $NS -- wget -qO- localhost

step "3. Check the Service and endpoints"
run kubectl get service troubleshooting-service -n $NS
run kubectl describe service troubleshooting-service -n $NS
run kubectl get endpoints troubleshooting-service -n $NS
run kubectl exec client -n $NS -- nslookup troubleshooting-service
run kubectl exec client -n $NS -- wget -qO- --timeout=3 http://troubleshooting-service

step "4. Break: Pod with a bad image"
run kubectl apply -f broken-pod.yaml
sleep 20
run kubectl get pod project-broken-pod -n $NS
run kubectl describe pod project-broken-pod -n $NS
run kubectl logs project-broken-pod -n $NS

step "5. Fix the Pod"
run kubectl apply -f fixed-pod.yaml
run kubectl wait pod/project-broken-pod -n $NS --for=condition=Ready --timeout=120s
run kubectl get pod project-broken-pod -n $NS

step "6. Break: Service selector"
run kubectl apply -f broken-service.yaml
sleep 3
run kubectl get endpoints troubleshooting-service -n $NS
run kubectl exec client -n $NS -- wget -qO- --timeout=3 http://troubleshooting-service
run kubectl get pods -n $NS --show-labels
run kubectl describe service troubleshooting-service -n $NS

step "7. Fix the Service"
run kubectl apply -f service.yaml
sleep 3
run kubectl get endpoints troubleshooting-service -n $NS
run kubectl exec client -n $NS -- wget -qO- --timeout=3 http://troubleshooting-service

step "8. Final state"
run kubectl get all -n $NS -l app=troubleshooting-app
run kubectl get events -n $NS --field-selector type=Warning --sort-by=.lastTimestamp
echo
echo "Clean up with: kubectl delete -f deployment.yaml -f service.yaml -f client-pod.yaml -f fixed-pod.yaml"
