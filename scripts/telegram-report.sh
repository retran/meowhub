#!/usr/bin/env bash
# Sends one message straight to the admin's Telegram chat via the Bot API —
# used for reports that must reach a human even when nothing else in the
# system can (a failed restore verification: ADR 0009, ADR 0020). This is
# infrastructure reporting, not a conversational reply, so it never goes
# through n8n.
#
# TELEGRAM_ADMIN_CHAT_ID is an interim mechanism: spec 0002 gives every
# admin a real identity and routes reports to all of them; until then this
# is the one chat id a deployment names by hand.
#
# TELEGRAM_API_BASE_URL, when set, replaces the whole endpoint instead of
# just the token — how tests stub this call offline (ADR 0015), never set
# in a real deployment.
set -euo pipefail

: "${TELEGRAM_ADMIN_CHAT_ID:?TELEGRAM_ADMIN_CHAT_ID must be set — see .env.example}"
MESSAGE="${1:?usage: scripts/telegram-report.sh <message>}"

if [ -n "${TELEGRAM_API_BASE_URL:-}" ]; then
  API_URL="$TELEGRAM_API_BASE_URL"
else
  TOKEN="${TELEGRAM_BOT_TOKEN:-${TELEGRAM_LOCAL_BOT_TOKEN:-}}"
  : "${TOKEN:?neither TELEGRAM_BOT_TOKEN nor TELEGRAM_LOCAL_BOT_TOKEN is set}"
  API_URL="https://api.telegram.org/bot${TOKEN}/sendMessage"
fi

payload="$(python3 -c "import json,sys; print(json.dumps({'chat_id': sys.argv[1], 'text': sys.argv[2]}))" "$TELEGRAM_ADMIN_CHAT_ID" "$MESSAGE")"
curl -fsS -X POST "$API_URL" -H 'Content-Type: application/json' -d "$payload" >/dev/null
