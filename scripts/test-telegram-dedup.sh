#!/usr/bin/env bash
# Proves spec 0001 A: a doubled update produces one effect (ADR 0027, 0033).
# Feeds the same update_id through the real normalize-and-dispatch
# sub-workflow twice and checks the dedup set persisted in the workflow's
# static data: the id must be recorded exactly once, not twice — which is
# what the shared logic actually keys on before deciding whether to reply.
# Requires the stack to be up (task up); this exercises the live n8n
# instance, not a mock.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"

if ! $COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: n8n is not running (run 'task up' first)"
  exit 0
fi

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "dedupentry0001",
  "name": "dedup-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "dedup-test", "responseMode": "responseNode", "options": {}},
     "id": "t0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "dedup-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "t0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "t0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "t0000000-0000-4000-8000-000000000003", "name": "Respond",
     "type": "n8n-nodes-base.respondToWebhook", "typeVersion": 1.1, "position": [560, 0]}
  ],
  "connections": {
    "Webhook": {"main": [[{"node": "Unwrap", "type": "main", "index": 0}]]},
    "Unwrap": {"main": [[{"node": "Dispatch", "type": "main", "index": 0}]]},
    "Dispatch": {"main": [[{"node": "Respond", "type": "main", "index": 0}]]}
  },
  "settings": {},
  "active": true
}
JSON
chmod 644 "$TMP"
docker compose cp "$TMP" n8n:/tmp/dedup-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/dedup-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=dedupentry0001 >/dev/null
$COMPOSE restart n8n >/dev/null
for i in $(seq 1 20); do
  h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done

UPDATE_ID=$(( RANDOM + 900000000 ))
PAYLOAD="{\"update\": {\"update_id\": ${UPDATE_ID}, \"message\": {\"from\": {\"id\": 1, \"language_code\": \"ru\"}, \"chat\": {\"id\": -999}, \"text\": \"dedup test\", \"message_thread_id\": null}}, \"source\": \"dedup-test\"}"

bash scripts/proxy-curl.sh /webhook/dedup-test -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" >/dev/null || true
sleep 1
bash scripts/proxy-curl.sh /webhook/dedup-test -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" >/dev/null || true
sleep 1

DEDUP_STATE="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -t -c \
  "select \"staticData\"::text from workflow_entity where id='tgdispatch00001';")"

# cleanup regardless of outcome
$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='dedupentry0001'; delete from webhook_entity where \"workflowId\"='dedupentry0001';" >/dev/null
rm -f "$TMP"

OCCURRENCES=$(echo "$DEDUP_STATE" | grep -o "${UPDATE_ID}" | wc -l | tr -d ' ')
if [ "$OCCURRENCES" != "1" ]; then
  echo "FAILED: update_id ${UPDATE_ID} recorded ${OCCURRENCES} time(s) in the dedup set, expected exactly 1"
  exit 1
fi
echo "PASS: the same update_id sent twice is recorded exactly once in the dedup set"
