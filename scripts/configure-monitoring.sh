#!/usr/bin/env bash
# Creates Uptime Kuma's admin account (first run only) and its monitors from
# this script, not the UI (ADR 0010: configuration is code). Idempotent: an
# existing monitor with the same name is left alone. Requires the stack to be
# up (task up).
#
# A push monitor's token is minted by Kuma, not chosen by a developer — the
# uptime-kuma-api library has no way to set it at creation, so this script
# writes the resulting push URL into .env itself, once, the first time each
# monitor is created. Its HEARTBEAT_*_URL is a generated credential after
# that, the same way a database's auto-assigned id is: never typed in by
# hand, and never invented up front.
set -euo pipefail

: "${UPTIME_KUMA_ADMIN_USERNAME:?UPTIME_KUMA_ADMIN_USERNAME not set}"
: "${UPTIME_KUMA_ADMIN_PASSWORD:?UPTIME_KUMA_ADMIN_PASSWORD not set}"

SCRIPT_TMP="$(mktemp)"
trap 'rm -f "$SCRIPT_TMP"' EXIT
cat > "$SCRIPT_TMP" <<PYEOF
from uptime_kuma_api import UptimeKumaApi, MonitorType

USERNAME = "${UPTIME_KUMA_ADMIN_USERNAME}"
PASSWORD = "${UPTIME_KUMA_ADMIN_PASSWORD}"

api = UptimeKumaApi("http://localhost:3001")
try:
    if api.need_setup():
        api.setup(USERNAME, PASSWORD)
        print("created the Kuma admin account")
    api.login(USERNAME, PASSWORD)

    existing = {m["name"]: m for m in api.get_monitors()}

    def upsert(name, **kwargs):
        if name in existing:
            print(f"exists: {name}")
            return existing[name]["id"]
        result = api.add_monitor(name=name, **kwargs)
        print(f"created: {name}")
        return result["monitorID"]

    upsert("postgres", type=MonitorType.PORT, hostname="postgres", port=5432, interval=30)
    upsert("proxy", type=MonitorType.PORT, hostname="proxy", port=443, interval=30)
    upsert(
        "n8n (through the proxy)",
        type=MonitorType.HTTP,
        url="https://proxy/healthz",
        ignoreTls=True,
        interval=30,
    )

    # (monitor name, .env variable, window in seconds — docs/standards/budgets.md)
    push_monitors = [
        ("drift check (heartbeat)", "HEARTBEAT_DRIFT_CHECK_URL", 86400),
        ("backup (heartbeat)", "HEARTBEAT_BACKUP_URL", 129600),  # 36h: nightly, generous
        ("restore verification (heartbeat)", "HEARTBEAT_RESTORE_VERIFY_URL", 2073600),  # 24d: Kuma's own interval cap, docs/standards/budgets.md
        ("digest tick (heartbeat)", "HEARTBEAT_DIGEST_URL", 7200),  # 2h: the tick is hourly (spec 0004 R14)
    ]
    for name, env_var, interval in push_monitors:
        monitor_id = upsert(name, type=MonitorType.PUSH, interval=interval)
        token = api.get_monitor(monitor_id)["pushToken"]
        print(f"PUSH_URL {env_var}=http://localhost:3001/api/push/{token}?status=up&msg=OK&ping=")

    # The SSO boundary is the only *login* gate (spec 0002 T10, R17a) — a
    # push token was never login-gated to begin with, so this changes
    # nothing about how heartbeats reach Kuma.
    api.set_settings(disableAuth=True, trustProxy=True, password=PASSWORD)
    print("disabled Kuma's own login — the proxy's forward-auth is the only gate now")
finally:
    api.disconnect()
PYEOF

output="$(bash scripts/kuma-run.sh "$SCRIPT_TMP")"
echo "$output"

echo "$output" | sed -n 's/^PUSH_URL //p' | while IFS='=' read -r env_var push_url; do
  # The URL above is Kuma's own container-internal view; from the host (and
  # from anything in this repository, which all runs on the host) it is
  # reachable on the published loopback port instead.
  host_url="$(echo "$push_url" | sed "s#localhost:3001#127.0.0.1:${UPTIME_KUMA_PORT}#")"
  escaped_url="${host_url//&/\\&}"   # & is special in sed's replacement text
  if [ -f .env ]; then
    if grep -q "^${env_var}=" .env; then
      sed -i.bak "s#^${env_var}=.*#${env_var}=${escaped_url}#" .env
      rm -f .env.bak
    else
      echo "${env_var}=${host_url}" >> .env
    fi
    echo "wrote ${env_var} to .env"
  fi
done

echo "monitoring configured"
