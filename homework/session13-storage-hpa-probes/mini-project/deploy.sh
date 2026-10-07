#!/usr/bin/env bash
# deploy.sh - Session 13 mini project: namespace -> PVC -> Deployment/Service -> HPA
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS=production-webapp

kubectl apply -f "${DIR}/namespace.yaml"
kubectl apply -f "${DIR}/pvc.yaml"
kubectl apply -f "${DIR}/deployment.yaml"
kubectl apply -f "${DIR}/service.yaml"
kubectl rollout status -n "$NS" deployment/web-app --timeout=180s
kubectl apply -f "${DIR}/hpa.yaml"

echo
kubectl get pvc,pods,svc,hpa -n "$NS"
echo
echo "Persistence test:"
echo "  POD=\$(kubectl get pods -n $NS -l app=web-app -o jsonpath='{.items[0].metadata.name}')"
echo "  kubectl exec -n $NS \$POD -- sh -c 'echo \"Student: Om Malviya\" > /data/student.txt'"
echo "  kubectl delete pod -n $NS \$POD && sleep 20"
echo "  kubectl exec -n $NS \$(kubectl get pods -n $NS -l app=web-app -o jsonpath='{.items[0].metadata.name}') -- cat /data/student.txt"
echo "Load test:   kubectl apply -f ${DIR}/load-generator.yaml && kubectl get hpa -n $NS -w"
