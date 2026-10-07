#!/usr/bin/env bash
# Rollback: point the Service back at the blue pods.
set -euo pipefail
NS=s10
kubectl -n "$NS" patch svc web-bg \
  -p '{"spec":{"selector":{"app":"web-bg","version":"blue"}}}'
echo "Selector now:"
kubectl -n "$NS" get svc web-bg -o jsonpath='{.spec.selector}'; echo
echo "Endpoints now:"
kubectl -n "$NS" get endpoints web-bg
