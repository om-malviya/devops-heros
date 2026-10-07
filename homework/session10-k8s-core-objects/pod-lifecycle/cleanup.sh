#!/usr/bin/env bash
# Remove every Pod created by this lab (namespace s10 is kept).
set -uo pipefail
NS=s10
kubectl -n "$NS" delete pod -l lab=pod-lifecycle --ignore-not-found --grace-period=5
kubectl -n "$NS" get pods -l lab=pod-lifecycle
