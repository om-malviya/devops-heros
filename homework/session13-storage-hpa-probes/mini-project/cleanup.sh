#!/usr/bin/env bash
# cleanup.sh - remove the Session 13 mini project (namespace deletion removes PVC and the dynamic PV).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -f "${DIR}/load-generator.yaml" --ignore-not-found=true
kubectl delete -f "${DIR}/hpa.yaml" -f "${DIR}/service.yaml" -f "${DIR}/deployment.yaml" -f "${DIR}/pvc.yaml" --ignore-not-found=true
kubectl delete -f "${DIR}/namespace.yaml" --ignore-not-found=true
echo "Done."
