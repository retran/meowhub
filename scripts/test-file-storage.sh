#!/usr/bin/env bash
# End-to-end proof of A7/A7a: the same bytes stored twice yield one path and
# are recognised as a duplicate; a corrupted byte is reported.
set -euo pipefail

TMP_STORAGE="$(mktemp -d)"
export FILE_STORAGE_PATH="$TMP_STORAGE"
trap 'rm -rf "$TMP_STORAGE"' EXIT

SRC="$(mktemp)"
echo "a fixture, not a real receipt" > "$SRC"

out1="$(bash scripts/file-store.sh "$SRC" text/plain test-process fixture.txt)"
hash1="$(echo "$out1" | tail -1)"
count1="$(find "$TMP_STORAGE" -type f | wc -l | tr -d ' ')"

out2="$(bash scripts/file-store.sh "$SRC" text/plain test-process fixture.txt)"
hash2="$(echo "$out2" | tail -1)"
count2="$(find "$TMP_STORAGE" -type f | wc -l | tr -d ' ')"

if [ "$hash1" != "$hash2" ]; then
  echo "FAILED: hashes differ across two stores of the same bytes"; exit 1
fi
if [ "$count1" != "1" ] || [ "$count2" != "1" ]; then
  echo "FAILED: expected exactly one stored file after two stores, got $count1 then $count2"; exit 1
fi
if ! echo "$out2" | grep -q "^duplicate:"; then
  echo "FAILED: second store was not recognised as a duplicate"; exit 1
fi
echo "PASS: same bytes stored twice -> one path, recognised as duplicate"

STORED_PATH="$(find "$TMP_STORAGE" -type f)"
chmod 644 "$STORED_PATH"
echo "corrupted" >> "$STORED_PATH"
if bash scripts/file-check-integrity.sh; then
  echo "FAILED: integrity check should have reported the corrupted file"; exit 1
fi
echo "PASS: a corrupted stored file is reported by the integrity check"
