#!/usr/bin/env bash
# deploy-all.sh - Deploy every Session 12 demo (ConfigMap, Secret, Ingress) into namespace s12.
# Works on k3s (Traefik) and on minikube (run `minikube addons enable ingress` first).
# The deliberately broken manifests in 05-troubleshooting/ are NOT applied here.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS=s12

echo "[1/5] Namespace"
kubectl apply -f "${DIR}/namespace.yaml"

echo "[2/5] ConfigMap demo"
kubectl apply -f "${DIR}/01-configmap/configmap.yaml"
kubectl apply -f "${DIR}/01-configmap/pod.yaml"

echo "[3/5] Secret demo"
kubectl apply -f "${DIR}/02-secret/secret.yaml"
kubectl apply -f "${DIR}/02-secret/pod.yaml"

echo "[4/5] Ingress demo (app1 + app2 + ingress)"
kubectl apply -f "${DIR}/03-ingress/app1-deployment.yaml"
kubectl apply -f "${DIR}/03-ingress/app2-deployment.yaml"
kubectl apply -f "${DIR}/03-ingress/ingress.yaml"

echo "[5/5] Waiting for workloads"
kubectl wait -n "$NS" --for=condition=Ready pod/configmap-demo pod/secret-demo --timeout=120s
kubectl rollout status -n "$NS" deployment/app1 --timeout=120s
kubectl rollout status -n "$NS" deployment/app2 --timeout=120s

echo
kubectl get configmap,secret,pods,svc,ingress -n "$NS"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
cat <<MSG

Deployed. Verify with:
  kubectl exec -n $NS configmap-demo -- env | grep -E 'APP_|LOG_LEVEL|THEME|UI_THEME'
  kubectl exec -n $NS configmap-demo -- cat /etc/config/app.properties
  kubectl exec -n $NS secret-demo    -- env | grep DB_
  kubectl exec -n $NS secret-demo    -- cat /etc/secrets/DB_PASSWORD
  curl -H 'Host: demo.local' http://${NODE_IP}/app1      # node IP (routable on a real node / VM)
  curl -H 'Host: demo.local' http://localhost/app1        # Colima on macOS forwards the VM's port 80
  # fallback on any cluster: kubectl port-forward -n kube-system svc/traefik 18080:80  -> http://localhost:18080
Optional /etc/hosts entry:   echo "${NODE_IP}  demo.local" | sudo tee -a /etc/hosts
MSG
