#!/usr/bin/env bash
# Restores the latest snapshot from RESTIC_REPOSITORY to a local directory —
# used for a real recovery and by scripts/verify-restore.sh alike (spec
# 0001 T14/T15, ADR 0009). Restoring is never destructive by itself: this
# only writes files to <target-dir>; loading them into a database is the
# caller's decision.
#
# Usage: scripts/restore.sh <target-dir>
set -euo pipefail

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set — see .env.example}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD must be set — see .env.example}"

TARGET_DIR="${1:?usage: scripts/restore.sh <target-dir>}"
mkdir -p "$TARGET_DIR"

export RESTORE_TARGET_DIR="$TARGET_DIR"
bash scripts/restic-run.sh "$RESTIC_REPOSITORY" restore latest --target /restore-output >&2

echo "restored the latest snapshot from ${RESTIC_REPOSITORY} into ${TARGET_DIR}"
