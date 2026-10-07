#!/usr/bin/env bash
# Remove everything created by the Session 08 task scripts and the compose file.
set -uo pipefail
cd "$(dirname "$0")"

for c in frontend backend db apache-host apache-bridge nginx-bind; do
  # docker rm -f exits 0 even when the container does not exist, so check first
  if docker container inspect "$c" >/dev/null 2>&1; then
    docker rm -f "$c" >/dev/null && echo "removed container $c"
  else
    echo "container $c not present"
  fi
done
for n in frontend-net backend-net db-net; do
  docker network rm "$n" >/dev/null 2>&1 && echo "removed network $n" || echo "network $n not present"
done
if [[ -f docker-compose.yml ]]; then
  if [[ -n "$(docker compose ps -aq 2>/dev/null)" ]]; then
    docker compose down -v --remove-orphans >/dev/null 2>&1 && echo "compose project removed"
  else
    echo "compose project not running"
  fi
fi
