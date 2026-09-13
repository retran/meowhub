#!/usr/bin/env bash
# Proves spec 0001 T16 / R13: drift detection actually runs on a schedule,
# not only when a developer remembers to invoke it. Checks the scheduler
# container's crontab is what's expected, then runs the exact same command
# cron would run, from inside that container, to prove it can really reach
# everything it needs (Docker socket, the network, Kuma) — not just that
# the schedule is configured on paper. Requires the stack to be up
# (task up).
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps scheduler --format '{{.State}}' 2>/dev/null | grep -q running; then
  echo "SKIPPED: the scheduler is not running (run 'task up' first)"
  exit 0
fi

if ! $COMPOSE exec -T scheduler crontab -l | grep -q "scripts/detect-drift.sh"; then
  echo "FAILED: the scheduler's crontab does not run scripts/detect-drift.sh"
  exit 1
fi
echo "PASS: the scheduler's crontab runs drift detection"

if ! $COMPOSE exec -T scheduler sh -c "cd /workspace && bash scripts/detect-drift.sh"; then
  echo "FAILED: drift detection did not run cleanly from inside the scheduler container"
  exit 1
fi
echo "PASS: drift detection runs cleanly from inside the scheduler container, exactly as cron would invoke it"
