#!/usr/bin/env bash
# Installs Argo CD into the current kube-context, waits for it, prints the
# initial admin password and the port-forward command.
# Usage: ./install-argocd.sh [--port-forward]
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Using kube-context: $(kubectl config current-context)"

echo "==> Creating namespace argocd"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying Argo CD manifests (${ARGOCD_VERSION})"
kubectl apply -n argocd --server-side --force-conflicts -f "${MANIFEST}"

echo "==> Waiting for Argo CD components to become ready (can take 2-5 min)"
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

echo
echo "UI:  https://localhost:8080   (user: admin, password above)"
echo "Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"

if [[ "${1:-}" == "--port-forward" ]]; then
  echo "==> Starting port-forward in the foreground (Ctrl+C to stop)"
  kubectl port-forward svc/argocd-server -n argocd 8080:443
fi
