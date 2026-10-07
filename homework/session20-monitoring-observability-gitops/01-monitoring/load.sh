#!/usr/bin/env bash
# Generates traffic against the sample app so the dashboard and alerts have data.
# Usage: ./load.sh [seconds]   (default 60). ~10% of requests hit /error on purpose.
set -euo pipefail
DURATION="${1:-60}"
BASE="${BASE_URL:-http://localhost:8000}"
end=$((SECONDS + DURATION))
while [ "$SECONDS" -lt "$end" ]; do
  curl -s -o /dev/null "$BASE/"
  curl -s -o /dev/null "$BASE/slow"
  if [ $((RANDOM % 10)) -eq 0 ]; then curl -s -o /dev/null "$BASE/error"; fi
  sleep 0.2
done
echo "done: sent traffic for ${DURATION}s to $BASE"
