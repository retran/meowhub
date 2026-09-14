#!/usr/bin/env bash
# Proves spec 0004 T7 (ADR 0046): the agent's loop refuses what no tool
# answers in its own words (A3), degrades honestly when the gateway is
# unreachable (A13), and stops at the round cap rather than looping
# when a model only ever calls tools.
#
# The test entry workflow calls the agent directly and responds with
# its output, so assertions are made against the reply the member
# would actually have received, not against a database side effect
# standing in for it.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: n8n is not running (run 'task up' first)"
  exit 0
fi

psql_meowhub() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" "$@"
}

fail=0
CHAT_ID=$(( RANDOM + 810000000 ))

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    delete from capture where member_id = ${MEMBER_ID};
    delete from member where id = ${MEMBER_ID};
  " >/dev/null 2>&1 || true
  $COMPOSE start model-gateway-stub >/dev/null 2>&1 || true
}
trap cleanup EXIT

ask() {
  local text="$1"
  local payload
  payload="$(python3 -c "
import json, sys
print(json.dumps({
  'member_id': int(sys.argv[1]),
  'chat_id': int(sys.argv[2]),
  'message_thread_id': None,
  'text': sys.argv[3],
  'language_hint': 'en',
  'channel_message_id': None
}))
" "$MEMBER_ID" "$CHAT_ID" "$text")"
  bash scripts/proxy-curl.sh /webhook/agent-loop-test -X POST -H 'Content-Type: application/json' -d "$payload" 2>/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "agenttestentry1",
  "name": "agent-loop-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "agent-loop-test", "responseMode": "responseNode", "options": {}},
     "id": "y0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "agent-loop-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "y0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "agentloop00001", "mode": "id"}, "options": {}},
     "id": "y0000000-0000-4000-8000-000000000002", "name": "Agent",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [300, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ $json }}", "options": {}},
     "id": "y0000000-0000-4000-8000-000000000003", "name": "Respond",
     "type": "n8n-nodes-base.respondToWebhook", "typeVersion": 1.1, "position": [520, 0]}
  ],
  "connections": {
    "Webhook": {"main": [[{"node": "Unwrap", "type": "main", "index": 0}]]},
    "Unwrap": {"main": [[{"node": "Agent", "type": "main", "index": 0}]]},
    "Agent": {"main": [[{"node": "Respond", "type": "main", "index": 0}]]}
  },
  "settings": {},
  "active": true
}
JSON
chmod 644 "$TMP"
docker compose cp "$TMP" n8n:/tmp/agent-loop-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/agent-loop-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=agenttestentry1 >/dev/null
$COMPOSE restart n8n >/dev/null
bash scripts/wait-for-n8n.sh
rm -f "$TMP"

reply_text() { python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    print((json.loads(raw) or {}).get('text') or '')
except Exception:
    print('')
"; }

# A3: a question no declared tool answers is refused in the agent's own
# words, naming what can be asked -- and with no figure in it.
refusal="$(ask 'can we afford a holiday next year' | reply_text)"
if [ -n "$refusal" ] && ! echo "$refusal" | grep -qE '[0-9]'; then
  echo "PASS: a question no tool answers is refused in the agent's own words, with no figure (A3)"
else
  echo "FAILED: expected a figure-free refusal, got '${refusal}'"
  fail=1
fi
if echo "$refusal" | grep -qiE "spend|category|balance|owed"; then
  echo "PASS: the refusal names what can be asked instead (A3, R6)"
else
  echo "FAILED: refusal does not name what can be asked instead: '${refusal}'"
  fail=1
fi

# The round cap: a model that only ever calls tools must be stopped by
# the loop itself, not by the model choosing to stop.
capped="$(ask 'LOOP_FOREVER_TEST please' | reply_text)"
if echo "$capped" | grep -qi "nothing is lost"; then
  echo "PASS: a model that only ever calls tools is stopped by the round cap (ADR 0046)"
else
  echo "FAILED: expected the round cap's honest fallback, got '${capped}'"
  fail=1
fi

# A13: the gateway is unreachable. The message is kept, the member is
# told something true, and no figure is invented.
$COMPOSE stop model-gateway-stub >/dev/null 2>&1
down_reply="$(ask 'how much did we spend this month' | reply_text)"
$COMPOSE start model-gateway-stub >/dev/null 2>&1
sleep 3

if echo "$down_reply" | grep -qi "nothing is lost" && ! echo "$down_reply" | grep -qE '[0-9]'; then
  echo "PASS: an unreachable gateway degrades to an honest sentence with no figure (A13)"
else
  echo "FAILED: expected the honest failure line with no digits, got '${down_reply}'"
  fail=1
fi

stored="$(psql_meowhub -t -A -c "select count(*) from capture where member_id = ${MEMBER_ID} and direction = 'inbound' and raw_text = 'how much did we spend this month';")"
if [ "$stored" = "1" ]; then
  echo "PASS: the message is stored even though the gateway never answered (A13, R6a)"
else
  echo "FAILED: expected the inbound message stored once, found ${stored}"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='agenttestentry1'; delete from webhook_entity where \"workflowId\"='agenttestentry1';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
