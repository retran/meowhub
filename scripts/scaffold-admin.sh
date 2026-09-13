#!/usr/bin/env bash
# Creates the first admin from the environment; refuses if any account
# exists (spec 0001 T17, R14e). The password is hashed with pgcrypto's
# bcrypt (never stored or logged in the clear) and marked initial —
# changing it on first sign-in is spec 0002's job, not this script's.
set -euo pipefail

: "${SCAFFOLD_ADMIN_EMAIL:?SCAFFOLD_ADMIN_EMAIL must be set — see .env.example}"
: "${SCAFFOLD_ADMIN_PASSWORD:?SCAFFOLD_ADMIN_PASSWORD must be set — see .env.example}"
: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER must be set — see .env.example}"
: "${POSTGRES_DB:?POSTGRES_DB must be set — see .env.example}"

COMPOSE="docker compose -f compose.yaml"

existing="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -t -A \
  -c "select count(*) from admin_account;")"
if [ "$existing" != "0" ]; then
  echo "REFUSED: an admin account already exists"
  exit 1
fi

# psql only interpolates :'var' when reading a script (stdin/-f), not with
# -c — piped via stdin so the email and password never touch a shell-quoted
# SQL string.
echo "insert into admin_account (email, password_hash) values (:'email', crypt(:'password', gen_salt('bf')));" \
  | $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
      -v email="$SCAFFOLD_ADMIN_EMAIL" -v password="$SCAFFOLD_ADMIN_PASSWORD" \
  >/dev/null

echo "created the first admin account: ${SCAFFOLD_ADMIN_EMAIL}"
