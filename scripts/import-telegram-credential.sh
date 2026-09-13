#!/usr/bin/env bash
# Imports the Telegram API credential from the environment — never
# committed, built at runtime and discarded. TELEGRAM_LOCAL_BOT_TOKEN is
# used for both poll and webhook triggers locally; a deployed host would
# use TELEGRAM_BOT_TOKEN instead (ADR 0033).
set -euo pipefail
: "${TELEGRAM_LOCAL_BOT_TOKEN:?TELEGRAM_LOCAL_BOT_TOKEN must be set — see .env.example}"

COMPOSE="docker compose -f compose.yaml"
TMP="$(mktemp)"
python3 -c "
import json, os
json.dump([{
  'id': 'tgapicred00001',
  'name': 'Telegram (household bot)',
  'type': 'telegramApi',
  'data': {'accessToken': os.environ['TELEGRAM_LOCAL_BOT_TOKEN'], 'baseUrl': 'https://api.telegram.org'}
}], open('$TMP', 'w'))
"
# mktemp creates the file mode 600; the container's node user is a
# different uid than the host user that Docker Desktop/OrbStack preserves
# on `cp`, so a restrictive mode is unreadable inside the container.
chmod 644 "$TMP"
docker compose cp "$TMP" n8n:/tmp/telegram-cred.json >&2
$COMPOSE exec -T n8n n8n import:credentials --input=/tmp/telegram-cred.json >&2
rm -f "$TMP"
echo "telegram credential imported"
