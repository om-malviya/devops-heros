#!/usr/bin/env bash
# Run all six Hello World containers on host ports 3001..3006 and curl each one.
# Idempotent: removes containers with the same names first.
set -euo pipefail
cd "$(dirname "$0")"

# name:image:hostport:containerport
APPS=(
  "hello-nodejs:hello-nodejs:3001:3000"
  "hello-python:hello-python:3002:5000"
  "hello-java:hello-java:3003:8080"
  "hello-apache:hello-apache:3004:80"
  "hello-react:hello-react:3005:80"
  "hello-nginx:hello-nginx:3006:80"
)

for entry in "${APPS[@]}"; do
  IFS=: read -r name image hostport contport <<< "$entry"
  docker rm -f "$name" >/dev/null 2>&1 || true
  echo "=== Starting ${name} on http://localhost:${hostport} (container port ${contport})"
  docker run -d --name "$name" -p "${hostport}:${contport}" "${image}:1.0"
done

echo
echo "=== Waiting for the apps to start..."
sleep 3

echo
docker ps --filter "name=hello-" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo
for entry in "${APPS[@]}"; do
  IFS=: read -r name image hostport contport <<< "$entry"
  echo "=== curl http://localhost:${hostport}  (${name})"
  curl -s --max-time 5 "http://localhost:${hostport}" | grep -o "<h1>.*</h1>\|<title>.*</title>" || echo "(no response yet)"
done
