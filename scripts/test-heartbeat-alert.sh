#!/usr/bin/env bash
# Proves spec 0001 T13's done-when directly: stopping a job produces an
# alert after its window. Creates its own scratch push monitor at Kuma's
# minimum interval so the test stays fast, pushes one heartbeat, then goes
# silent and asserts Kuma marks it down once the window has passed —
# exactly the dead-man's-switch behaviour ADR 0020 depends on. Cleans up the
# scratch monitor regardless of outcome. Requires the stack to be up
# (task up).
set -euo pipefail

: "${UPTIME_KUMA_ADMIN_USERNAME:?UPTIME_KUMA_ADMIN_USERNAME not set}"
: "${UPTIME_KUMA_ADMIN_PASSWORD:?UPTIME_KUMA_ADMIN_PASSWORD not set}"

SCRIPT_TMP="$(mktemp)"
trap 'rm -f "$SCRIPT_TMP"' EXIT
cat > "$SCRIPT_TMP" <<PYEOF
import time
import urllib.request
from uptime_kuma_api import UptimeKumaApi, MonitorType, MonitorStatus

USERNAME = "${UPTIME_KUMA_ADMIN_USERNAME}"
PASSWORD = "${UPTIME_KUMA_ADMIN_PASSWORD}"
NAME = "heartbeat-alert-test"
INTERVAL = 20  # Kuma's own minimum

api = UptimeKumaApi("http://localhost:3001")
monitor_id = None
try:
    api.login(USERNAME, PASSWORD)

    for m in api.get_monitors():
        if m["name"] == NAME:
            api.delete_monitor(m["id"])

    # The library has no way to choose a push monitor's token at creation
    # (unlike scripts/configure-monitoring.sh's real one, this scratch
    # monitor is thrown away at the end of this run anyway) — read back
    # whichever one Kuma minted.
    result = api.add_monitor(
        name=NAME, type=MonitorType.PUSH,
        interval=INTERVAL, maxretries=0,
    )
    monitor_id = result["monitorID"]
    token = api.get_monitor(monitor_id)["pushToken"]

    urllib.request.urlopen(
        f"http://localhost:3001/api/push/{token}?status=up&msg=OK&ping="
    ).read()
    print("pushed one heartbeat")

    time.sleep(INTERVAL * 3)

    beats = api.get_heartbeats().get(monitor_id, [])
    if not beats:
        print("FAILED: no heartbeat recorded for the scratch monitor")
        raise SystemExit(1)
    last = beats[-1]
    if last["status"] != MonitorStatus.DOWN:
        print(f"FAILED: expected DOWN after the window passed with no push, got {last['status']}")
        raise SystemExit(1)
    print("PASS: the scratch monitor went DOWN after its window passed with no push")
finally:
    if monitor_id is not None:
        api.delete_monitor(monitor_id)
    api.disconnect()
PYEOF

bash scripts/kuma-run.sh "$SCRIPT_TMP"
