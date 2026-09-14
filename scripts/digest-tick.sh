#!/usr/bin/env bash
# Runs the digest tick (spec 0004 T11, R9/R10/R17) the way cron invokes
# it: the running n8n container's own webhook, from inside it -- the
# same pattern scripts/auto-confirm-quiet.sh uses.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
response="$($COMPOSE exec -T n8n wget -q -O- --post-data='{}' --header='Content-Type: application/json' \
  http://localhost:5678/webhook/digest-tick)"
echo "$response"

# R14/ADR 0020: the heartbeat is pushed only when the tick actually
# answered. A tick that failed, or one whose reply carries an error,
# stays silent -- and silence is what raises the alert.
python3 -c "
import json, sys
payload = json.loads(sys.argv[1] or '{}')
sys.exit(1 if payload.get('error') or 'sent' not in payload else 0)
" "$response"

if [ -n "${HEARTBEAT_DIGEST_URL:-}" ]; then
  bash scripts/heartbeat-curl.sh "$HEARTBEAT_DIGEST_URL"
fi
