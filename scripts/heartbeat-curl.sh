#!/usr/bin/env bash
# Pushes a Kuma heartbeat URL, working the same whether the caller is a
# developer's shell or the scheduler container (spec 0001 T16): the URL
# written to .env by scripts/configure-monitoring.sh is the host's loopback
# view (127.0.0.1:UPTIME_KUMA_PORT), which does not resolve from inside
# another container — /.dockerenv is the standard way to tell the two
# apart, and from inside one, Kuma is reachable by its compose service name
# instead.
set -euo pipefail

URL="${1:?usage: scripts/heartbeat-curl.sh <heartbeat-url>}"

if [ -f /.dockerenv ]; then
  URL="$(echo "$URL" | sed "s#127\.0\.0\.1:${UPTIME_KUMA_PORT}#uptime-kuma:3001#")"
fi

curl -fsS "$URL" >/dev/null
