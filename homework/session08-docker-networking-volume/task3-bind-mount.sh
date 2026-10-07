#!/usr/bin/env bash
# Task 3: bind mount a local folder into Nginx, change the file, see the change live.
set -euo pipefail
cd "$(dirname "$0")"

NAME=nginx-bind
HTML_DIR="$PWD/bind-mount/html"
FILE="$HTML_DIR/index.html"
ORIGINAL='<h1>Hello students</h1>'

echo "=== 1. Local folder and index.html"
mkdir -p "$HTML_DIR"
echo "$ORIGINAL" > "$FILE"
ls -l "$HTML_DIR"; cat "$FILE"

echo
echo "=== 2. Run Nginx with the folder bind-mounted"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p 8082:80 \
  -v "$HTML_DIR:/usr/share/nginx/html:ro" nginx:alpine
sleep 2
docker inspect -f '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}} ({{.Mode}}){{end}}' "$NAME"; echo

echo
echo "=== 3. Access the site"
curl -s http://localhost:8082

echo
echo "=== 4. Modify index.html on the HOST (container is NOT restarted)"
STAMP="$(date '+%Y-%m-%d %H:%M:%S')"
echo "<h1>Hello students - file updated at ${STAMP}</h1>" > "$FILE"
cat "$FILE"

echo
echo "=== 5. Access again - change is visible immediately"
curl -s http://localhost:8082
echo
echo "--- container status (same uptime, no restart):"
docker ps --filter "name=$NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo
echo "=== 6. Restore the original content so the repo file stays 'Hello students'"
echo "$ORIGINAL" > "$FILE"
curl -s http://localhost:8082
