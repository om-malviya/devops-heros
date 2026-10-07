#!/usr/bin/env bash
# Stop and remove all six Hello World containers (ignores ones that do not exist).
set -uo pipefail

for name in hello-nodejs hello-python hello-java hello-apache hello-react hello-nginx; do
  # docker rm -f exits 0 even when the container does not exist, so check first
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed $name"
  else
    echo "$name not running"
  fi
done

# Optional: also delete the images
if [[ "${1:-}" == "--images" ]]; then
  docker rmi hello-nodejs:1.0 hello-python:1.0 hello-java:1.0 hello-apache:1.0 hello-react:1.0 hello-nginx:1.0 || true
fi
