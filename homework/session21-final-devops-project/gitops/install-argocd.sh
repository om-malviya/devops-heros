#!/usr/bin/env bash
# Install Argo CD into the current kubectl context and register the TaskBoard dev Application.
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"
APP_FILE="$(cd "$(dirname "$0")" && pwd)/argocd/application-dev.yaml"

echo "==> Installing Argo CD ${ARGOCD_VERSION} into namespace argocd"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for the Argo CD server to become ready"
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s

echo "==> Registering the TaskBoard application"
kubectl apply -f "$APP_FILE"

echo "==> Initial admin password (change it after first login):"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

cat <<MSG

Open the UI:
  kubectl -n argocd port-forward svc/argocd-server 8443:443
  https://localhost:8443   (user: admin)

Watch the sync:
  kubectl -n argocd get applications.argoproj.io taskboard-dev -w
MSG
