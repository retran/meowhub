#!/usr/bin/env bash
# Imports every committed workflow into n8n, imports the Telegram
# credential from the environment, and applies the delivery mode
# (ADR 0010, ADR 0033, ADR 0040). Idempotent. This is what makes `task up`
# reproduce the whole system from the repository and .env, never from
# manual clicks.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
shopt -s nullglob
files=(workflows/*.json)
if [ ${#files[@]} -eq 0 ]; then
  echo "no workflows to import"
else
  for f in "${files[@]}"; do
    name="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$f")"
    id="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['id'])" "$f")"
    active="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('active', False))" "$f")"

    docker compose cp "$f" "n8n:/tmp/import-${id}.json" >/dev/null
    $COMPOSE exec -T n8n n8n import:workflow --input="/tmp/import-${id}.json" >&2

    # telegram-poll and telegram-webhook are always imported inactive
    # (committed as active:false) — apply-telegram-mode.sh, driven by
    # TELEGRAM_DELIVERY_MODE, is the sole authority on which one runs.
    if [ "$active" = "True" ]; then
      $COMPOSE exec -T n8n n8n publish:workflow --id="$id" >&2 || true
    fi
    echo "imported: ${name}"
  done
fi

bash scripts/import-telegram-credential.sh
bash scripts/apply-telegram-mode.sh

echo "restarting n8n to register triggers and activation changes"
