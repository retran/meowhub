#!/usr/bin/env bash
# Runs restic against one repository, mounting what it needs and passing
# offsite S3-compatible credentials only when the repository is remote — a
# local path and an S3 destination take the exact same restic command,
# which is what spec 0001 T14's done-when actually asks for. Shared by
# scripts/backup.sh, scripts/restore.sh and scripts/verify-restore.sh so
# "how do we even invoke restic" exists in exactly one place.
#
# Usage: scripts/restic-run.sh <repository> <restic-args...>
set -euo pipefail

REPOSITORY="$1"
shift

: "${RESTIC_PASSWORD:?RESTIC_PASSWORD not set}"
: "${FILE_STORAGE_PATH:?FILE_STORAGE_PATH not set}"

STAGING_DIR="$(cd "$(dirname "$0")/.." && pwd)/.data/backup-staging"
mkdir -p "$STAGING_DIR" "$FILE_STORAGE_PATH"
files_abs="$(cd "$FILE_STORAGE_PATH" && pwd)"

docker_args=(
  --rm
  -v "${STAGING_DIR}:/staging:ro"
  -v "${files_abs}:/files:ro"
)

# A restore needs somewhere writable to land — never the live staging or
# file storage paths, always a scratch directory the caller names.
if [ -n "${RESTORE_TARGET_DIR:-}" ]; then
  mkdir -p "$RESTORE_TARGET_DIR"
  restore_abs="$(cd "$RESTORE_TARGET_DIR" && pwd)"
  docker_args+=(-v "${restore_abs}:/restore-output")
fi

case "$REPOSITORY" in
  /*|./*|../*)
    # A local path: resolve it to an absolute path first, so the same path
    # string works as RESTIC_REPOSITORY both inside and outside the
    # container regardless of either one's working directory.
    mkdir -p "$REPOSITORY"
    repository_resolved="$(cd "$REPOSITORY" && pwd)"
    docker_args+=(-v "${repository_resolved}:${repository_resolved}")
    ;;
  *)
    # A remote backend (s3:, b2:, ...): credentials, no bind mount.
    : "${BACKUP_OFFSITE_ACCESS_KEY:?BACKUP_OFFSITE_ACCESS_KEY not set}"
    : "${BACKUP_OFFSITE_SECRET_KEY:?BACKUP_OFFSITE_SECRET_KEY not set}"
    repository_resolved="$REPOSITORY"
    docker_args+=(
      -e "AWS_ACCESS_KEY_ID=${BACKUP_OFFSITE_ACCESS_KEY}"
      -e "AWS_SECRET_ACCESS_KEY=${BACKUP_OFFSITE_SECRET_KEY}"
    )
    ;;
esac

docker run "${docker_args[@]}" \
  -e "RESTIC_REPOSITORY=${repository_resolved}" \
  -e "RESTIC_PASSWORD=${RESTIC_PASSWORD}" \
  restic/restic:0.17.3 "$@"
