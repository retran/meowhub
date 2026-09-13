#!/usr/bin/env bash
# Activates exactly one of the two Telegram entry-point workflows based on
# TELEGRAM_DELIVERY_MODE (ADR 0033): "polling" for local, "webhook" for
# deployed. Flipping the mode is a change to .env and re-running this
# script — no workflow file, no code, nothing else.
set -euo pipefail

MODE="${TELEGRAM_DELIVERY_MODE:?TELEGRAM_DELIVERY_MODE must be set to polling or webhook}"
COMPOSE="docker compose -f compose.yaml"

case "$MODE" in
  polling)
    $COMPOSE exec -T n8n n8n publish:workflow --id=tgpoll000000001 >&2
    $COMPOSE exec -T n8n n8n unpublish:workflow --id=tgwebhook00001 >&2 2>/dev/null || \
      $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
        "update workflow_entity set active=false where id='tgwebhook00001';" >&2
    echo "mode: polling (telegram-poll active, telegram-webhook inactive)"
    ;;
  webhook)
    $COMPOSE exec -T n8n n8n publish:workflow --id=tgwebhook00001 >&2
    $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
      "update workflow_entity set active=false where id='tgpoll000000001';" >&2
    echo "mode: webhook (telegram-webhook active, telegram-poll inactive)"
    ;;
  *)
    echo "TELEGRAM_DELIVERY_MODE must be 'polling' or 'webhook', got: $MODE" >&2
    exit 1
    ;;
esac
