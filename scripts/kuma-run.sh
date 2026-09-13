#!/usr/bin/env bash
# Runs a Python script against the live Uptime Kuma using its real
# Socket.IO API (the uptime-kuma-api library — there is no REST API for
# monitor management). The script is attached to Kuma's own network
# namespace, so "localhost:3001" reaches it with no dependency on Compose's
# generated network name.
#
# Usage: scripts/kuma-run.sh <path-to-python-script>
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"

if ! $COMPOSE ps uptime-kuma --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: uptime-kuma is not running (run 'task up' first)"
  exit 0
fi

KUMA_CID="$($COMPOSE ps -q uptime-kuma)"

docker run --rm --network "container:${KUMA_CID}" \
  -v "$(cd "$(dirname "$1")" && pwd)/$(basename "$1"):/script.py:ro" \
  python:3.12-alpine \
  sh -c "pip install -q uptime-kuma-api >/dev/null && python3 /script.py"
