#!/usr/bin/env bash
# deploy-all.sh - Deploy every Session 13 demo: volumes, HPA app, probes (namespace s13) and the
# mini project (namespace production-webapp). The load generator is NOT started here.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS=s13

echo "[1/5] Namespace"
kubectl apply -f "${DIR}/namespace.yaml"

echo "[2/5] Volumes (emptyDir, hostPath, static PV/PVC, dynamic PVC)"
kubectl apply -f "${DIR}/01-kubernetes-volumes/emptydir-pod.yaml"
kubectl apply -f "${DIR}/01-kubernetes-volumes/hostpath-pod.yaml"
kubectl apply -f "${DIR}/01-kubernetes-volumes/pv.yaml"
kubectl apply -f "${DIR}/01-kubernetes-volumes/pvc-static.yaml"
kubectl apply -f "${DIR}/01-kubernetes-volumes/pod-static-pvc.yaml"
kubectl apply -f "${DIR}/01-kubernetes-volumes/pvc-dynamic.yaml"
kubectl apply -f "${DIR}/01-kubernetes-volumes/pod-dynamic-pvc.yaml"

echo "[3/5] HPA demo (metrics-server must be running: kubectl top nodes)"
kubectl top nodes >/dev/null 2>&1 || echo "  WARNING: metrics API not available. k3s ships metrics-server; on minikube run: minikube addons enable metrics-server"
kubectl apply -f "${DIR}/02-hpa/deployment.yaml"
kubectl apply -f "${DIR}/02-hpa/service.yaml"
kubectl apply -f "${DIR}/02-hpa/hpa.yaml"

echo "[4/5] Probes"
kubectl apply -f "${DIR}/03-probes/liveness.yaml"
kubectl apply -f "${DIR}/03-probes/readiness.yaml"
kubectl apply -f "${DIR}/03-probes/startup.yaml"

echo "[5/5] Mini project"
"${DIR}/mini-project/deploy.sh"

echo
kubectl rollout status -n "$NS" deployment/cpu-app --timeout=180s
kubectl get pv
kubectl get pvc,pods,svc,hpa -n "$NS"
cat <<MSG

Next steps:
  ${DIR}/02-hpa/load_generator.sh        # start load, then: kubectl get hpa -n s13 -w
  ${DIR}/02-hpa/load_generator.sh --stop
MSG
