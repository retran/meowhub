#!/bin/sh
# Fails loudly at startup if a required prompt or tool file is missing
# (ADR 0025, ADR 0039, spec 0001 T9/R17a, spec 0003 A29). Checking that
# /prompts and /tools are merely non-empty was not enough — each holds a
# README.md that keeps the directory non-empty forever, so a workflow's
# own prompt file could vanish and the check would still pass. This
# checks the specific files a capture actually needs.
set -e

REQUIRED_FILES="
/prompts/agent/v1/system.md
/tools/record_transaction.json
/tools/find_merchant.json
"

for f in $REQUIRED_FILES; do
  if [ ! -s "$f" ]; then
    echo "FATAL: ${f} is missing or empty — mount it before starting n8n (ADR 0025/0039)" >&2
    exit 1
  fi
done

exec "$@"
