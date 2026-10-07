#!/usr/bin/env bash
# Build all six Hello World images for Session 06.
set -euo pipefail
cd "$(dirname "$0")"

# folder:image
APPS=(
  "nodejs-app:hello-nodejs"
  "python-app:hello-python"
  "java-app:hello-java"
  "Apache-app:hello-apache"
  "React-app:hello-react"
  "nginx-app:hello-nginx"
)

for entry in "${APPS[@]}"; do
  dir="${entry%%:*}"
  image="${entry##*:}"
  echo "=== Building ${image}:1.0 from ./${dir}"
  docker build -t "${image}:1.0" "./${dir}"
done

echo
echo "=== Images built:"
docker images --filter "reference=hello-*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
