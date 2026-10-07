#!/usr/bin/env bash
# Task 2: Apache (httpd) container on the host network, reachable directly on port 80.
set -euo pipefail

NAME=apache-host

echo "=== Pull the Apache2 (httpd) image"
docker pull httpd:alpine

docker rm -f "$NAME" >/dev/null 2>&1 || true

echo
echo "=== Run with --network host (no -p needed: container shares the host's network stack)"
docker run -d --name "$NAME" --network host httpd:alpine
sleep 2

echo
docker ps --filter "name=$NAME" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo "(PORTS column is empty with host networking - there is no port mapping)"
echo
echo "--- docker port $NAME:"; docker port "$NAME" || true
echo "--- network of the container:"
docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$NAME"; echo

echo
echo "=== Access Apache directly on port 80"
if curl -s --max-time 5 http://localhost:80; then
  echo "(served directly from host port 80)"
else
  echo "!! localhost:80 did not answer."
  if [[ "$(uname -s)" == "Darwin" ]]; then
    cat <<'MSG'
On macOS, Docker runs inside a Linux VM, so --network host binds port 80 inside the VM,
not on the Mac itself. Docker Desktop 4.34+ can forward it if
"Settings -> Resources -> Network -> Enable host networking" is turned on.
Verifying from inside the container instead:
MSG
    docker exec "$NAME" wget -qO- http://localhost:80
    echo
    echo "Fallback with a published port (bridge network):"
    docker rm -f apache-bridge >/dev/null 2>&1 || true
    docker run -d --name apache-bridge -p 8080:80 httpd:alpine >/dev/null
    sleep 2
    curl -s http://localhost:8080
  fi
fi

echo
echo "=== On Linux, httpd is visible as a host listener:"
echo "    ss -ltnp | grep ':80 '   (or: sudo lsof -i :80)"
