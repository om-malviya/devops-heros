#!/usr/bin/env bash
# cleanup.sh - Remove everything Session 12 created (including troubleshooting scenarios).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS=s12

for f in 05-troubleshooting/*.yaml 03-ingress/*.yaml 02-secret/*.yaml 01-configmap/*.yaml; do
  kubectl delete -f "${DIR}/${f}" --ignore-not-found=true
done
kubectl delete namespace "$NS" --ignore-not-found=true

echo "Done. If you added 'demo.local' to /etc/hosts, remove it with:"
echo "  sudo sed -i.bak '/demo.local/d' /etc/hosts"
