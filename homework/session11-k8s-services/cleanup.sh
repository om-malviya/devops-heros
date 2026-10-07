#!/usr/bin/env bash
# Remove everything from session 11 by deleting the namespace.
set -uo pipefail
kubectl delete namespace s11 --ignore-not-found
