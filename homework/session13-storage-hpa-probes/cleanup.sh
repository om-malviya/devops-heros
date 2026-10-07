#!/usr/bin/env bash
# cleanup.sh - Remove everything Session 13 created.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete -f "${DIR}/02-hpa/load-generator.yaml" --ignore-not-found=true
"${DIR}/mini-project/cleanup.sh"
for f in 03-probes/*.yaml 02-hpa/hpa.yaml 02-hpa/service.yaml 02-hpa/deployment.yaml \
         01-kubernetes-volumes/pod-dynamic-pvc.yaml 01-kubernetes-volumes/pvc-dynamic.yaml \
         01-kubernetes-volumes/pod-static-pvc.yaml 01-kubernetes-volumes/pvc-static.yaml \
         01-kubernetes-volumes/hostpath-pod.yaml 01-kubernetes-volumes/emptydir-pod.yaml; do
  kubectl delete -f "${DIR}/${f}" --ignore-not-found=true
done
kubectl delete namespace s13 --ignore-not-found=true
# The static PV is cluster-scoped and has reclaimPolicy Retain, so it must be removed explicitly.
kubectl delete -f "${DIR}/01-kubernetes-volumes/pv.yaml" --ignore-not-found=true
echo "Done. hostPath data left on the node under /tmp/s13-hostpath-data and /tmp/s13-static-pv (remove by hand if needed)."
