#!/usr/bin/env bash
# Runs the auto-confirm-quiet workflow (spec 0003 T12, R7c) the way
# cron invokes it: hitting the real running n8n container's own
# webhook from inside its own container, the same "docker compose exec"
# pattern scripts/detect-drift.sh already uses from the scheduler.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
$COMPOSE exec -T n8n wget -q -O- --post-data='' http://localhost:5678/webhook/auto-confirm-quiet
