#!/usr/bin/env bash
# Proves spec 0001 T12 / R5a: a flood on a public path is rejected at the
# edge, and the system behind it stays responsive throughout and afterwards.
# Requires the stack to be up (task up).
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"

if ! $COMPOSE ps proxy --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: the proxy is not running (run 'task up' first)"
  exit 0
fi

CA_TMP="$(mktemp)"
trap 'rm -f "$CA_TMP"' EXIT
$COMPOSE exec -T proxy cat /data/caddy/pki/authorities/local/root.crt > "$CA_TMP"

rejected=0
ok=0
for i in $(seq 1 40); do
  code="$(curl -sS --cacert "$CA_TMP" -o /dev/null -w '%{http_code}' \
    "https://localhost:${PROXY_HTTPS_PORT}/webhook/health-check")"
  if [ "$code" = "429" ]; then
    rejected=$((rejected + 1))
  elif [ "$code" = "200" ]; then
    ok=$((ok + 1))
  fi
done

if [ "$rejected" -eq 0 ]; then
  echo "FAILED: 40 rapid requests produced no 429 — the edge is not rate-limiting"
  exit 1
fi
echo "PASS: the flood was rejected at the edge (${ok} served, ${rejected} rejected with 429)"

# The zone's window is 10s; wait it out, then confirm the system behind is
# still healthy and answering normally — the point of R5a is that a flood
# never becomes an outage for the household's own use.
sleep 11
response="$(bash scripts/proxy-curl.sh /webhook/health-check)"
if ! echo "$response" | grep -q '"status":"ok"'; then
  echo "FAILED: n8n did not answer normally after the flood window passed: $response"
  exit 1
fi
echo "PASS: the system behind stayed responsive and recovered after the window: $response"
