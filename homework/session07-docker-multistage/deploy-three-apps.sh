#!/usr/bin/env bash
# Task 3: deploy three different application types (Node.js, Python, Java)
# using the Dockerfiles from Session 06. Builds, runs, curls each, shows docker ps.
set -euo pipefail
cd "$(dirname "$0")"

S06=../session06-docker-hello-world

# name:folder:hostport:containerport
APPS=(
  "hello-nodejs:nodejs-app:3001:3000"
  "hello-python:python-app:3002:5000"
  "hello-java:java-app:3003:8080"
)

for entry in "${APPS[@]}"; do
  IFS=: read -r name dir hostport contport <<< "$entry"
  echo "=== Building ${name}:1.0 from ${S06}/${dir}"
  docker build -t "${name}:1.0" "${S06}/${dir}"
done

echo
for entry in "${APPS[@]}"; do
  IFS=: read -r name dir hostport contport <<< "$entry"
  docker rm -f "$name" >/dev/null 2>&1 || true
  echo "=== Running ${name} on http://localhost:${hostport}"
  docker run -d --name "$name" -p "${hostport}:${contport}" "${name}:1.0"
done

echo
echo "=== Waiting for apps to start..."
sleep 3

echo
docker ps --filter "name=hello-" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo
for entry in "${APPS[@]}"; do
  IFS=: read -r name dir hostport contport <<< "$entry"
  echo "=== curl http://localhost:${hostport}  (${name})"
  curl -s --max-time 5 "http://localhost:${hostport}" || echo "(no response yet)"
done

echo
echo "=== Image sizes"
docker images --filter "reference=hello-*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
