#!/usr/bin/env bash
# Task 1: build the multi-stage image, run it on 8080, verify message and docker ps.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=multistage-app:1.0
NAME=multistage-app

docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "=== docker build (multi-stage)"
docker build -t "$IMAGE" ./multi-stage-app

echo
echo "=== docker run on port 8080"
docker run -d --name "$NAME" -p 8080:8080 "$IMAGE"
sleep 3

echo
echo "=== curl http://localhost:8080"
curl -s http://localhost:8080

echo
echo "=== docker ps (port 8080)"
docker ps --filter "name=$NAME"

echo
echo "=== image size"
docker images "$IMAGE"
