#!/usr/bin/env bash
# Proves spec 0004 A14 / R4a: every figure the agent puts in front of a
# member traces to a tool result from that same exchange, and no figure
# appears that does not (ADR 0046).
#
# This is the check that replaces the old design's structural
# guarantee, in which the model could not emit a number at all. It is
# therefore the one test in this slice that must be able to fail: it
# starts by proving the checker rejects a fabricated figure, because a
# traceability check that always passes is worth nothing.
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
CHAT_ID=$(( RANDOM + 830000000 ))

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
}
trap cleanup EXIT

# The checker, used both on the negative control and on every real
# exchange below. A figure in the reply is traceable when its own
# value, or the minor-unit value it renders ("18.00" -> 1800), appears
# somewhere in the tool results the agent was given.
cat > /tmp/traceability_check.py <<'PYEOF'
import json, re, sys

def numbers_in(value, acc):
    if isinstance(value, bool) or value is None:
        return acc
    if isinstance(value, (int, float)):
        acc.add(str(int(value)))
        return acc
    if isinstance(value, str):
        for token in re.findall(r"-?\d+(?:[.,]\d+)?", value):
            acc.add(token.replace(",", "."))
            try:
                acc.add(str(int(float(token.replace(",", ".")))))
            except ValueError:
                pass
        return acc
    if isinstance(value, dict):
        for v in value.values():
            numbers_in(v, acc)
        return acc
    if isinstance(value, list):
        for v in value:
            numbers_in(v, acc)
        return acc
    return acc

def check(reply, tool_results):
    available = numbers_in(tool_results, set())
    # Every way a figure from the database can legitimately be written.
    expanded = set(available)
    for n in list(available):
        try:
            as_int = int(float(n))
        except ValueError:
            continue
        expanded.add(f"{as_int/100:.2f}")       # minor units rendered as money
        expanded.add(f"{as_int/100:.2f}".replace(".", ","))
        expanded.add(str(as_int))

    untraceable = []
    for token in re.findall(r"-?\d+(?:[.,]\d+)?", reply or ""):
        normalised = token.replace(",", ".")
        candidates = {token, normalised}
        try:
            candidates.add(str(int(round(float(normalised) * 100))))
            candidates.add(str(int(float(normalised))))
        except ValueError:
            pass
        if not (candidates & expanded):
            untraceable.append(token)
    return untraceable

if __name__ == "__main__":
    payload = json.loads(sys.stdin.read() or "{}")
    bad = check(payload.get("text") or "", payload.get("tool_results") or [])
    print(json.dumps(bad))
PYEOF

# --- the negative control: the checker must reject a made-up figure --
control_bad="$(python3 /tmp/traceability_check.py <<'JSON'
{"text": "this_month: 18.00 € spent, which is 42% more than usual.",
 "tool_results": [{"tool": "spend_total", "result": {"rows": [{"amount_minor": 1800}]}}]}
JSON
)"
if echo "$control_bad" | grep -q '"42"'; then
  echo "PASS: the checker rejects a figure that appears in no tool result (negative control)"
else
  echo "FAILED: the checker did not catch a fabricated figure -- it proves nothing. Got: ${control_bad}"
  fail=1
fi
control_good="$(python3 /tmp/traceability_check.py <<'JSON'
{"text": "this_month: 18.00 € spent.",
 "tool_results": [{"tool": "spend_total", "result": {"rows": [{"amount_minor": 1800}]}}]}
JSON
)"
if [ "$control_good" = "[]" ]; then
  echo "PASS: the checker accepts a figure the database actually returned (negative control)"
else
  echo "FAILED: the checker rejected a legitimate figure: ${control_good}"
  fail=1
fi

ask() {
  local text="$1"
  local payload
  payload="$(python3 -c "
import json, sys
print(json.dumps({
  'member_id': int(sys.argv[1]), 'chat_id': int(sys.argv[2]), 'message_thread_id': None,
  'text': sys.argv[3], 'language_hint': 'en', 'channel_message_id': None
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

# --- every golden question, end to end ------------------------------
check_question() {
  local question="$1"
  local response untraceable
  response="$(ask "$question")"
  untraceable="$(echo "$response" | python3 /tmp/traceability_check.py)"
  if [ "$untraceable" = "[]" ]; then
    echo "PASS: every figure traces to a tool result — \"${question}\" (A14)"
  else
    echo "FAILED: untraceable figures ${untraceable} in the reply to \"${question}\""
    echo "        reply was: $(echo "$response" | python3 -c "import json,sys; print((json.load(sys.stdin) or {}).get('text'))")"
    fail=1
  fi
}

check_question "how much did we spend this month"
check_question "what did we spend the most on this month"
check_question "how much do we owe in total"
check_question "what is our headroom on the credit card"
check_question "what do we have in total"
check_question "how many things are waiting for review"
check_question "what were the biggest expenses this month"

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='agenttestentry1'; delete from webhook_entity where \"workflowId\"='agenttestentry1';" >/dev/null
rm -f /tmp/traceability_check.py

if [ "$fail" != "0" ]; then
  exit 1
fi
