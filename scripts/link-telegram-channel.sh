#!/usr/bin/env bash
# An admin links a member's Telegram id to their account (ADR 0030, R6c) —
# never self-service. Run by an admin (over SSH, matching this system's
# operational model until spec 0006's app exists) from the docker host;
# reaches PostgREST directly over the compose network, never through the
# public proxy path (R16c's local-token exception to R16b).
#
# Usage: scripts/link-telegram-channel.sh <admin_member_id> <member_id> <telegram_external_id>
set -euo pipefail

: "${PGRST_JWT_SECRET:?PGRST_JWT_SECRET not set}"

ADMIN_MEMBER_ID="${1:?usage: link-telegram-channel.sh <admin_member_id> <member_id> <telegram_external_id>}"
MEMBER_ID="${2:?usage: link-telegram-channel.sh <admin_member_id> <member_id> <telegram_external_id>}"
EXTERNAL_ID="${3:?usage: link-telegram-channel.sh <admin_member_id> <member_id> <telegram_external_id>}"

TOKEN="$(bash scripts/mint-local-jwt.sh hh_admin "$ADMIN_MEMBER_ID")"

COMPOSE="docker compose -f compose.yaml"
CID="$($COMPOSE ps -q postgrest)"

response="$(docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 -sS -w '\nSTATUS:%{http_code}' \
  -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
  -d "{\"member_id\": ${MEMBER_ID}, \"kind\": \"telegram\", \"external_id\": \"${EXTERNAL_ID}\", \"linked_by\": ${ADMIN_MEMBER_ID}}" \
  http://localhost:3000/member_channel)"
status="${response##*STATUS:}"
body="${response%$'\n'STATUS:*}"

if [ "$status" = "201" ]; then
  echo "linked: member ${MEMBER_ID} <- telegram:${EXTERNAL_ID} (by admin ${ADMIN_MEMBER_ID})"
  echo "$body"
else
  echo "FAILED (${status}): $body" >&2
  exit 1
fi
