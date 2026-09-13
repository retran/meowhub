#!/usr/bin/env bash
# Proves spec 0001 T18's done-when: the suite exercises a path that would
# call a model — a real n8n workflow, calling OPENROUTER_BASE_URL exactly
# the way a real feature will — and makes no external request. The stub
# stamps every response with a provider name a real OpenRouter call could
# never produce; checking for it is how this test tells the two apart
# without needing to sniff network traffic.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: n8n is not running (run 'task up' first)"
  exit 0
fi

response="$(bash scripts/proxy-curl.sh /webhook/model-gateway-smoke-test)"
if ! echo "$response" | grep -q '"provider":"meowhub-local-stub"'; then
  echo "FAILED: expected the local stub's provider in the response, got: $response"
  exit 1
fi
echo "PASS: a real n8n workflow called OPENROUTER_BASE_URL and got the local stub, not a real request: $response"
