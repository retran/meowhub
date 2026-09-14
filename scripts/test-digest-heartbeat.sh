#!/usr/bin/env bash
# Proves spec 0004 A11/R14: a digest that stops being sent raises an
# alert. The tick pushes a heartbeat only when it actually answered, so
# preventing the job is preventing the push -- and after the window,
# silence is the alarm (ADR 0020).
#
# A scratch push monitor at Kuma's minimum interval stands in for the
# real one, so the test takes a minute rather than two hours. Requires
# the stack to be up (task up).
set -euo pipefail

: "${UPTIME_KUMA_ADMIN_USERNAME:?UPTIME_KUMA_ADMIN_USERNAME not set}"
: "${UPTIME_KUMA_ADMIN_PASSWORD:?UPTIME_KUMA_ADMIN_PASSWORD not set}"
: "${UPTIME_KUMA_PORT:?UPTIME_KUMA_PORT not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: n8n is not running (run 'task up' first)"
  exit 0
fi

NAME="digest-heartbeat-test"
INTERVAL=20

CREATE="$(mktemp)"; CHECK="$(mktemp)"
trap 'rm -f "$CREATE" "$CHECK"' EXIT

cat > "$CREATE" <<PYEOF
from uptime_kuma_api import UptimeKumaApi, MonitorType

api = UptimeKumaApi("http://localhost:3001")
try:
    api.login("${UPTIME_KUMA_ADMIN_USERNAME}", "${UPTIME_KUMA_ADMIN_PASSWORD}")
    for m in api.get_monitors():
        if m["name"] == "${NAME}":
            api.delete_monitor(m["id"])
    result = api.add_monitor(name="${NAME}", type=MonitorType.PUSH, interval=${INTERVAL}, maxretries=0)
    print("TOKEN " + api.get_monitor(result["monitorID"])["pushToken"])
finally:
    api.disconnect()
PYEOF

TOKEN="$(bash scripts/kuma-run.sh "$CREATE" | sed -n 's/^TOKEN //p')"
if [ -z "$TOKEN" ]; then
  echo "SKIPPED: could not create the scratch monitor (is uptime-kuma running?)"
  exit 0
fi

fail=0

# 1. the tick runs and pushes -- the monitor is up.
HEARTBEAT_DIGEST_URL="http://127.0.0.1:${UPTIME_KUMA_PORT}/api/push/${TOKEN}?status=up&msg=OK&ping=" \
  bash scripts/digest-tick.sh >/dev/null

# 2. and then it is prevented from running: nothing pushes again.
sleep $(( INTERVAL * 3 ))

cat > "$CHECK" <<PYEOF
import time
from uptime_kuma_api import UptimeKumaApi, MonitorStatus

api = UptimeKumaApi("http://localhost:3001")
try:
    api.login("${UPTIME_KUMA_ADMIN_USERNAME}", "${UPTIME_KUMA_ADMIN_PASSWORD}")
    monitor = next(m for m in api.get_monitors() if m["name"] == "${NAME}")
    # Kuma pushes the heartbeat history over its socket after the
    # connection settles, so an immediate read can arrive empty and say
    # nothing about whether the job pushed.
    def flatten(value):
        # Kuma delivers heartbeats over its socket in batches, and the
        # library hands them back either as a list of beats or as a list
        # of those batches depending on what arrived when.
        for item in value or []:
            if isinstance(item, dict):
                yield item
            elif isinstance(item, list):
                yield from flatten(item)

    beats = []
    for _ in range(10):
        beats = list(flatten(api.get_heartbeats().get(monitor["id"], [])))
        if beats:
            break
        time.sleep(2)
    try:
        if not beats:
            print("FAILED: the digest tick pushed no heartbeat at all")
            raise SystemExit(1)
        if beats[0]["status"] != MonitorStatus.UP:
            print("FAILED: the tick's own heartbeat was not recorded as up")
            raise SystemExit(1)
        if beats[-1]["status"] != MonitorStatus.DOWN:
            print(f"FAILED: expected DOWN once the window passed with the digest prevented, got {beats[-1]['status']}")
            raise SystemExit(1)
        print("PASS: a successful tick pushes a heartbeat, and preventing the digest raises the alert once its window passes (A11, R14)")
    finally:
        api.delete_monitor(monitor["id"])
finally:
    api.disconnect()
PYEOF

bash scripts/kuma-run.sh "$CHECK" || fail=1

exit "$fail"
