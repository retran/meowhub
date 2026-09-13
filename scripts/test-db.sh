#!/usr/bin/env bash
# Creates a throwaway database inside the running postgres service, applies
# migrations, runs pgTAP tests, tears down. This is task test:db (spec 0001,
# R15) — one command, clean checkout, identical locally and in CI (ADR 0034).
# Everything runs in containers: no native database install required.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
DB_NAME="meowhub_test_$$"
SUPERUSER="${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER must be set}"
SUPERPASS="${POSTGRES_SUPERUSER_PASSWORD:?POSTGRES_SUPERUSER_PASSWORD must be set}"
TEST_DB_URL="postgres://${SUPERUSER}:${SUPERPASS}@postgres:5432/${DB_NAME}?sslmode=disable"

cleanup() {
  $COMPOSE exec -T postgres dropdb -U "$SUPERUSER" --if-exists "$DB_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

$COMPOSE up -d --wait postgres

$COMPOSE exec -T postgres createdb -U "$SUPERUSER" "$DB_NAME"
$COMPOSE exec -T postgres psql -U "$SUPERUSER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c "create extension if not exists pgtap;" >/dev/null

$COMPOSE run --rm -T \
  -e DATABASE_URL="$TEST_DB_URL" \
  -v "$(pwd)/db/migrations:/db/migrations:ro" \
  migrate --migrations-dir /db/migrations --schema-file /tmp/schema.sql up >/dev/null

fail=0
for f in db/tests/*.sql; do
  echo "── $f ──"
  if ! $COMPOSE exec -T postgres psql -U "$SUPERUSER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$f"; then
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "FAILED"
  exit 1
fi
echo "ALL PASSED"
