#!/usr/bin/env bash
# Re-hashes every stored file and reports a mismatch or a missing file
# (ADR 0019, spec 0001 A7a). Exits non-zero if any check fails.
set -euo pipefail
: "${FILE_STORAGE_PATH:?FILE_STORAGE_PATH must be set — see .env.example}"

fail=0
if [ -d "$FILE_STORAGE_PATH" ]; then
  while IFS= read -r -d '' path; do
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
    expected="$(basename "$path")"
    if [ "$actual" != "$expected" ]; then
      echo "MISMATCH: ${path} — expected ${expected}, got ${actual}"
      fail=1
    fi
  done < <(find "$FILE_STORAGE_PATH" -type f -print0)
fi

if [ "$fail" -ne 0 ]; then
  echo "integrity check FAILED"
  exit 1
fi
echo "integrity check passed"
