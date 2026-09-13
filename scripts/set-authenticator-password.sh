#!/usr/bin/env bash
# Sets the authenticator role's password from the environment — never
# committed, and never embedded in a migration file (spec 0002 T2, R15b).
# Idempotent: safe to run on every task migrate.
set -euo pipefail

: "${DB_ROLE_AUTHENTICATOR_PASSWORD:?DB_ROLE_AUTHENTICATOR_PASSWORD must be set — see .env.example}"
: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER must be set — see .env.example}"
: "${POSTGRES_DB:?POSTGRES_DB must be set — see .env.example}"

COMPOSE="docker compose -f compose.yaml"

echo "alter role authenticator with password :'password';" \
  | $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
      -v password="$DB_ROLE_AUTHENTICATOR_PASSWORD" \
  >/dev/null

echo "authenticator password set"
