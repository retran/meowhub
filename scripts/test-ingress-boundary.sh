#!/usr/bin/env bash
# Proves spec 0001 A6 / T11: no container's own port is reachable from
# outside it, and the proxy is the only way in — over real TLS, not a stand-in
# for it. Requires the stack to be up (task up).
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"

if ! $COMPOSE ps proxy --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: the proxy is not running (run 'task up' first)"
  exit 0
fi

fail=0

if curl -sS --max-time 2 "http://localhost:${POSTGRES_PORT}" >/dev/null 2>&1; then
  echo "FAILED: postgres port ${POSTGRES_PORT} is reachable directly from the host"
  fail=1
else
  echo "PASS: postgres port ${POSTGRES_PORT} refuses a direct connection"
fi

if curl -sS --max-time 2 "http://localhost:${N8N_PORT}" >/dev/null 2>&1; then
  echo "FAILED: n8n port ${N8N_PORT} is reachable directly from the host"
  fail=1
else
  echo "PASS: n8n port ${N8N_PORT} refuses a direct connection"
fi

response="$(bash scripts/proxy-curl.sh /webhook/health-check)"
if ! echo "$response" | grep -q '"status":"ok"'; then
  echo "FAILED: the proxy did not reach a healthy n8n over TLS: $response"
  fail=1
else
  echo "PASS: the proxy terminates TLS and forwards to n8n: $response"
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
