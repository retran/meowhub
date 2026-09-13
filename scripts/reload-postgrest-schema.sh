#!/usr/bin/env bash
# A real gap found in spec 0003 T8: PostgREST caches the database schema
# at startup and has no reason to notice a migration that ran after it —
# every table and column this project has added since postgrest first
# came up (spec 0002 T8) was invisible to it until something happened to
# restart the container. Every migration must end with this: PostgREST
# supports NOTIFY-driven reloads without a restart, so this is cheap
# enough to run every time, not something to remember only when a
# request mysteriously 404s.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps postgrest --format '{{.State}}' 2>/dev/null | grep -q running; then
  exit 0
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -c "notify pgrst, 'reload schema';" >/dev/null
echo "postgrest schema cache reloaded"
