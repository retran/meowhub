#!/usr/bin/env bash
# Proves spec 0001 T14's done-when directly: a snapshot exists, it is
# ciphertext (not a decoration on top of plaintext dumps sitting next to
# it), and the offsite variable is the only difference for a second
# destination — proven by pointing "offsite" at a second local path and
# getting an independent snapshot from the exact same command. Requires the
# stack to be up (task up).
set -euo pipefail

: "${RESTIC_PASSWORD:?RESTIC_PASSWORD not set}"
: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${FILE_STORAGE_PATH:?FILE_STORAGE_PATH not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps postgres --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: postgres is not running (run 'task up' first)"
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

export RESTIC_REPOSITORY="${WORK_DIR}/local-repo"
export BACKUP_OFFSITE_REPOSITORY="${WORK_DIR}/offsite-repo"   # a second local path stands in for S3 here
# backup.sh pushes its heartbeat last, after both destinations succeed —
# this test cares about the backup, not the real push monitor's token, so
# it points at Kuma's own root, which always answers 200.
export HEARTBEAT_BACKUP_URL="http://127.0.0.1:${UPTIME_KUMA_PORT}/"

if ! bash scripts/backup.sh; then
  echo "FAILED: backup.sh did not complete (see output above)"
  exit 1
fi

for label in "local:${RESTIC_REPOSITORY}" "offsite:${BACKUP_OFFSITE_REPOSITORY}"; do
  name="${label%%:*}"
  repo="${label#*:}"

  count="$(bash scripts/restic-run.sh "$repo" snapshots --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")"
  if [ "$count" -lt 1 ]; then
    echo "FAILED: no snapshot found in the ${name} repository"
    exit 1
  fi
  echo "PASS: a snapshot exists in the ${name} repository (${count})"

  if grep -rq "bootstrap_probe" "$repo" 2>/dev/null; then
    echo "FAILED: a known plaintext string from the dump was found on disk in ${repo} — the repository is not ciphertext"
    exit 1
  fi
  echo "PASS: ${name} repository is ciphertext — no plaintext dump content readable on disk"
done

echo "PASS: local and offsite came from the exact same backup.sh, one variable apart"
