#!/bin/sh
# Fails loudly at startup if the prompt or tool directories are not mounted
# or are empty (ADR 0025, ADR 0039, spec 0001 T9/R17a). A silently missing
# mount would otherwise mean every capture fails at the first real request
# instead of at deploy time, when it is cheap to notice.
set -e

for d in /prompts /tools; do
  if [ ! -d "$d" ] || [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
    echo "FATAL: ${d} is missing or empty — mount it before starting n8n (ADR 0025/0039)" >&2
    exit 1
  fi
done

exec "$@"
