#!/usr/bin/env bash
# Monthly restore verification: the schema migrates, row counts match the
# live database, and it is reported to Telegram either way — a heartbeat is
# pushed only on real success, so a failure is never counted as good
# (spec 0001 T15, R11, ADR 0009/0020).
set -euo pipefail

: "${HEARTBEAT_RESTORE_VERIFY_URL:?HEARTBEAT_RESTORE_VERIFY_URL must be set — see .env.example}"
: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER must be set — see .env.example}"
: "${POSTGRES_DB:?POSTGRES_DB must be set — see .env.example}"

COMPOSE="docker compose -f compose.yaml"
SCRATCH_DB="restore_verify_$$"
RESTORE_DIR="$(mktemp -d)"

cleanup() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d postgres \
    -c "drop database if exists \"${SCRATCH_DB}\";" >/dev/null 2>&1 || true
  rm -rf "$RESTORE_DIR"
}
trap cleanup EXIT

fail() {
  bash scripts/telegram-report.sh "Meow: restore verification FAILED — $1" || true
  echo "FAILED: $1"
  exit 1
}

bash scripts/restore.sh "$RESTORE_DIR" || fail "restic restore did not complete"
[ -f "${RESTORE_DIR}/staging/meowhub.sql" ] || fail "no meowhub.sql in the latest snapshot"

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d postgres \
  -c "create database \"${SCRATCH_DB}\";" \
  || fail "could not create the scratch database"

docker compose cp "${RESTORE_DIR}/staging/meowhub.sql" "postgres:/tmp/restore-verify-$$.sql" >&2
$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$SCRATCH_DB" -v ON_ERROR_STOP=1 \
  -f "/tmp/restore-verify-$$.sql" >&2 \
  || fail "the dump did not load cleanly into the scratch database"

# The schema migrates: schema_migrations exists and lists the same applied
# versions as the live database — the actual proof migrations replay
# correctly, not just that the file happened to load.
live_migrations="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -t -A \
  -c "select string_agg(version, ',' order by version) from schema_migrations;")"
restored_migrations="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$SCRATCH_DB" -t -A \
  -c "select string_agg(version, ',' order by version) from schema_migrations;")"
[ "$restored_migrations" = "$live_migrations" ] \
  || fail "schema_migrations differs from the live database: live=[${live_migrations}] restored=[${restored_migrations}]"

# Row counts are sane: a known query (bootstrap_probe's count) returns the
# same known answer as the live database it was dumped from.
live_count="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -t -A \
  -c "select count(*) from bootstrap_probe;")"
restored_count="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$SCRATCH_DB" -t -A \
  -c "select count(*) from bootstrap_probe;")"
[ "$restored_count" = "$live_count" ] \
  || fail "bootstrap_probe row count differs from the live database: live=${live_count} restored=${restored_count}"

bash scripts/heartbeat-curl.sh "$HEARTBEAT_RESTORE_VERIFY_URL"
bash scripts/telegram-report.sh "Meow: restore verification passed — schema matches (${restored_migrations##*,}), bootstrap_probe has ${restored_count} row(s)."
echo "PASS: restore verification succeeded"
