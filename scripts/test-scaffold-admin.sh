#!/usr/bin/env bash
# Proves spec 0001 T17's done-when directly: it works once, refuses the
# second time, and a missing required variable names it and exits. Runs
# against a throwaway database, never the real dev one — this creates a
# permanent row, and the point of the test is not to leave one behind.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_SUPERUSER_PASSWORD:?POSTGRES_SUPERUSER_PASSWORD not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps postgres --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: postgres is not running (run 'task up' first)"
  exit 0
fi

SCRATCH_DB="scaffold_admin_test_$$"
cleanup() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d postgres \
    -c "drop database if exists \"${SCRATCH_DB}\";" >/dev/null 2>&1 || true
}
trap cleanup EXIT

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d postgres \
  -c "create database \"${SCRATCH_DB}\";" >/dev/null
$COMPOSE run --rm -e "DATABASE_URL=postgres://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERUSER_PASSWORD}@postgres:5432/${SCRATCH_DB}?sslmode=disable" \
  migrate --migrations-dir /db/migrations --schema-file /tmp/schema.sql up >&2

export POSTGRES_DB="$SCRATCH_DB"
export SCAFFOLD_ADMIN_EMAIL="admin@example.test"
export SCAFFOLD_ADMIN_PASSWORD="test-initial-password"

if ! bash scripts/scaffold-admin.sh; then
  echo "FAILED: the first scaffold-admin run should have succeeded"
  exit 1
fi

row="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$SCRATCH_DB" -t -A \
  -c "select password_is_initial, (crypt('${SCAFFOLD_ADMIN_PASSWORD}', password_hash) = password_hash) from admin_account where email='${SCAFFOLD_ADMIN_EMAIL}';")"
if [ "$row" != "t|t" ]; then
  echo "FAILED: expected an initial-password row whose hash verifies the password we gave it, got: ${row}"
  exit 1
fi
echo "PASS: the first run creates an admin account with a verifiable password hash, marked initial"

if bash scripts/scaffold-admin.sh 2>/dev/null; then
  echo "FAILED: a second run should have been refused"
  exit 1
fi
count="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$SCRATCH_DB" -t -A \
  -c "select count(*) from admin_account;")"
if [ "$count" != "1" ]; then
  echo "FAILED: expected exactly one admin account after a refused second run, got ${count}"
  exit 1
fi
echo "PASS: a second run is refused, and no second account is created"

unset SCAFFOLD_ADMIN_EMAIL
output="$(bash scripts/scaffold-admin.sh 2>&1)" && missing_rc=0 || missing_rc=$?
if [ "$missing_rc" -eq 0 ]; then
  echo "FAILED: scaffold-admin.sh should not succeed with SCAFFOLD_ADMIN_EMAIL unset"
  exit 1
fi
if ! echo "$output" | grep -q "SCAFFOLD_ADMIN_EMAIL must be set"; then
  echo "FAILED: a missing SCAFFOLD_ADMIN_EMAIL should have named itself and exited, got: ${output}"
  exit 1
fi
echo "PASS: a missing required variable names itself and the component exits"
