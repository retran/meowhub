#!/usr/bin/env bash
# curl through the ingress proxy (spec 0001 T11), trusting Caddy's own local
# certificate authority instead of skipping verification: this exercises the
# real TLS termination, not a stand-in for it.
#
# Usage: scripts/proxy-curl.sh <path> [extra curl args...]
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
PATH_SUFFIX="$1"
shift

CA_TMP="$(mktemp)"
trap 'rm -f "$CA_TMP"' EXIT
$COMPOSE exec -T proxy cat /data/caddy/pki/authorities/local/root.crt > "$CA_TMP"

curl -sS --cacert "$CA_TMP" "https://localhost:${PROXY_HTTPS_PORT}${PATH_SUFFIX}" "$@"
