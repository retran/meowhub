#!/usr/bin/env bash
# Proves the public path reaches n8n end to end, through the proxy, over TLS
# (spec 0001 A5, T11): a request in gets a reply out. Requires the stack to be
# up (task up) — it is not part of the always-offline pgTAP suite, per
# ADR 0015.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"

if ! $COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: n8n is not running (run 'task up' first)"
  exit 0
fi

response="$(bash scripts/proxy-curl.sh /webhook/health-check)"
if ! echo "$response" | grep -q '"status":"ok"'; then
  echo "FAILED: unexpected response from health-check webhook: $response"
  exit 1
fi
echo "PASS: health-check webhook responded: $response"
