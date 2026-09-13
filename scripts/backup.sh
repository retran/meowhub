#!/usr/bin/env bash
# Nightly restic snapshot, local then offsite (ADR 0009, spec 0001 T14).
# What is backed up: a logical pg_dump of meowhub's own database and of
# n8n's (ADR 0004: separate databases, so this is genuinely two dumps, not
# one), plus the content-addressed file storage volume. Secrets are never
# backed up here — they live in each admin's password manager (ADR 0009).
set -euo pipefail

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set — see .env.example}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD must be set — see .env.example}"
: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER must be set — see .env.example}"
: "${HEARTBEAT_BACKUP_URL:?HEARTBEAT_BACKUP_URL must be set — see .env.example}"

COMPOSE="docker compose -f compose.yaml"
STAGING_DIR="$(cd "$(dirname "$0")/.." && pwd)/.data/backup-staging"
mkdir -p "$STAGING_DIR"

$COMPOSE exec -T postgres pg_dump -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" \
  > "${STAGING_DIR}/meowhub.sql"
$COMPOSE exec -T postgres pg_dump -U "$POSTGRES_SUPERUSER" -d n8n \
  > "${STAGING_DIR}/n8n.sql"

snapshot() {
  local repository="$1"
  bash scripts/restic-run.sh "$repository" snapshots >/dev/null 2>&1 \
    || bash scripts/restic-run.sh "$repository" init
  bash scripts/restic-run.sh "$repository" backup /staging /files
  # Retention: 7 daily, 4 weekly, 12 monthly (ADR 0009) — deep enough that
  # corruption noticed weeks later is still recoverable, small enough to be
  # free in practice at this data size.
  bash scripts/restic-run.sh "$repository" forget \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
}

snapshot "$RESTIC_REPOSITORY"
echo "backed up to ${RESTIC_REPOSITORY}"

if [ -n "${BACKUP_OFFSITE_REPOSITORY:-}" ]; then
  snapshot "$BACKUP_OFFSITE_REPOSITORY"
  echo "backed up to ${BACKUP_OFFSITE_REPOSITORY}"
else
  echo "BACKUP_OFFSITE_REPOSITORY not set — local only (fine in dev, not in a real deployment)"
fi

bash scripts/heartbeat-curl.sh "$HEARTBEAT_BACKUP_URL"
echo "backup complete"
