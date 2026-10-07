#!/usr/bin/env bash
# Task 1: three containers (frontend, backend, db), three networks,
# backend attached to two networks, connectivity checks.
# Idempotent: removes existing containers/networks first.
set -euo pipefail

NETS=(frontend-net backend-net db-net)
CONTAINERS=(frontend backend db)

echo "=== Cleaning up previous run"
for c in "${CONTAINERS[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
for n in "${NETS[@]}"; do docker network rm "$n" >/dev/null 2>&1 || true; done

echo
echo "=== Creating 3 networks"
for n in "${NETS[@]}"; do docker network create --driver bridge "$n"; done
docker network ls --filter "name=-net"

echo
echo "=== Creating containers"
# frontend: nginx on frontend-net only, published on host 8091
docker run -d --name frontend --network frontend-net -p 8091:80 nginx:alpine
# backend: nginx, starts on backend-net ...
docker run -d --name backend --network backend-net nginx:alpine
# ... and is ALSO connected to frontend-net (backend is in 2 networks)
docker network connect frontend-net backend
# db: mysql on db-net and backend-net (reachable from backend, not from frontend)
docker run -d --name db --network db-net \
  -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=demo mysql:8
docker network connect backend-net db

sleep 2
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo
echo "=== Networks per container"
for c in "${CONTAINERS[@]}"; do
  printf "%-9s -> " "$c"
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}' "$c"
  echo
done

echo
echo "=== Waiting for MySQL to accept connections (up to 90s)"
for i in $(seq 1 45); do
  if docker exec db mysqladmin ping -h 127.0.0.1 -uroot -prootpass123 --silent >/dev/null 2>&1; then
    echo "MySQL is up after ~$((i*2))s"; break
  fi
  sleep 2
done

echo
echo "=== Connectivity checks FROM backend (in both networks)"
echo "--- ping frontend";        docker exec backend ping -c 2 -W 2 frontend
echo "--- wget http://frontend"; docker exec backend wget -qO- http://frontend | grep -o "<title>.*</title>"
echo "--- getent hosts db";      docker exec backend getent hosts db
echo "--- nc -zv db 3306";       docker exec backend nc -zv -w 3 db 3306

echo
echo "=== Connectivity checks FROM frontend (frontend-net only)"
echo "--- getent hosts backend"; docker exec frontend getent hosts backend
echo "--- wget http://backend";  docker exec frontend wget -qO- http://backend | grep -o "<title>.*</title>"
echo "--- getent hosts db (expected to FAIL: frontend is not in a network with db)"
docker exec frontend getent hosts db || echo "no DNS entry for db from frontend (expected)"
echo "--- ping db (expected to FAIL)"
docker exec frontend ping -c 1 -W 2 db 2>&1 || echo "frontend cannot reach db (expected)"

echo
echo "=== Host access: curl http://localhost:8091 (frontend)"
curl -s http://localhost:8091 | grep -o "<title>.*</title>"
