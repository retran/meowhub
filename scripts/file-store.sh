#!/usr/bin/env bash
# Stores a file content-addressed by SHA-256 (ADR 0019, spec 0001 T7).
# Usage: file-store.sh <path> <media-type> <uploaded-by> [original-name]
#
# The path on FILE_STORAGE_PATH is derived from the hash (ab/cd/<hash>), so
# storing the same bytes twice is free and detected by lookup, not by
# heuristic — this is also the idempotency key statement import needs later
# (ADR 0013).
set -euo pipefail

SRC="${1:?usage: file-store.sh <path> <media-type> <uploaded-by> [original-name]}"
MEDIA_TYPE="${2:?media type required}"
UPLOADED_BY="${3:?uploaded-by (member id or process name) required}"
ORIGINAL_NAME="${4:-$(basename "$SRC")}"

: "${FILE_STORAGE_PATH:?FILE_STORAGE_PATH must be set — see .env.example}"

HASH="$(shasum -a 256 "$SRC" | awk '{print $1}')"
SUBDIR="${HASH:0:2}/${HASH:2:2}"
DEST_DIR="${FILE_STORAGE_PATH}/${SUBDIR}"
DEST="${DEST_DIR}/${HASH}"
SIZE="$(wc -c < "$SRC" | tr -d ' ')"

mkdir -p "$DEST_DIR"

if [ -f "$DEST" ]; then
  echo "duplicate: ${HASH} already stored at ${DEST}"
else
  cp "$SRC" "$DEST"
  chmod 444 "$DEST"   # content-addressed bytes are never modified in place
  echo "stored: ${HASH} at ${DEST}"
fi

COMPOSE="docker compose -f compose.yaml"
$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
  -c "select set_config('meowhub.actor', '${UPLOADED_BY}', false);
      insert into file (sha256, media_type, size_bytes, original_name, uploaded_by)
      values ('${HASH}', '${MEDIA_TYPE}', ${SIZE}, '${ORIGINAL_NAME}', '${UPLOADED_BY}')
      on conflict (sha256) do nothing;" >/dev/null

echo "$HASH"
