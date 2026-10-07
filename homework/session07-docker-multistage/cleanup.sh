#!/usr/bin/env bash
# Remove the containers started by run-multistage.sh and deploy-three-apps.sh.
set -uo pipefail
for name in multistage-app hello-nodejs hello-python hello-java; do
  # docker rm -f exits 0 even when the container does not exist, so check first
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed $name"
  else
    echo "$name not running"
  fi
done
