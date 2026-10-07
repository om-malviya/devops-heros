#!/usr/bin/env bash
# Flip 100% of traffic from blue to green by patching the Service selector.
set -euo pipefail
NS=s10
kubectl -n "$NS" patch svc web-bg \
  -p '{"spec":{"selector":{"app":"web-bg","version":"green"}}}'
echo "Selector now:"
kubectl -n "$NS" get svc web-bg -o jsonpath='{.spec.selector}'; echo
echo "Endpoints now:"
kubectl -n "$NS" get endpoints web-bg
