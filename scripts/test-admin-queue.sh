#!/usr/bin/env bash
# Proves spec 0003 T14's A43: an admin lists the unconfirmed queue in
# chat and confirms it all in one reply, so the queue is drainable
# before the app exists (R20).
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
ADMIN_TG=$(( RANDOM + 970000000 ))
MEMBER_TG=$(( RANDOM + 975000000 ))

ADMIN_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('admin', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  insert into member_channel (member_id, kind, external_id, linked_by) values (${ADMIN_ID}, 'telegram', '${ADMIN_TG}', ${ADMIN_ID});
  insert into member_channel (member_id, kind, external_id, linked_by) values (${MEMBER_ID}, 'telegram', '${MEMBER_TG}', ${ADMIN_ID});
" >/dev/null

PAYMENT_ACCT="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='asset' and active limit 1;" | grep -E '^[0-9]+$' | tail -1)"
CATEGORY_ACCT="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='expense' and name='groceries' limit 1;" | grep -E '^[0-9]+$' | tail -1)"

new_unconfirmed() {
  local submitter="$1"
  local amount="$2"
  local txn_id
  txn_id="$(psql_meowhub -t -A -c "
    select set_config('meowhub.actor', 'test-suite', false);
    set role hh_agent;
    insert into transaction (date, submitter, source, confirmation_state) values (current_date, ${submitter}, 'text', 'unconfirmed') returning id;
  " | grep -E '^[0-9]+$' | tail -1)"
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    set role hh_agent;
    insert into posting (transaction_id, account_id, amount, currency) values (${txn_id}, ${PAYMENT_ACCT}, -${amount}, 'EUR');
    insert into posting (transaction_id, account_id, amount, currency) values (${txn_id}, ${CATEGORY_ACCT}, ${amount}, 'EUR');
  " >/dev/null
  echo "$txn_id"
}

TXN_A="$(new_unconfirmed "$ADMIN_ID" 500)"
TXN_B="$(new_unconfirmed "$MEMBER_ID" 700)"

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    delete from capture where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from posting where transaction_id in (${TXN_A}, ${TXN_B});
    delete from transaction where id in (${TXN_A}, ${TXN_B});
    delete from member_channel where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from member where id in (${ADMIN_ID}, ${MEMBER_ID});
  " >/dev/null 2>&1 || true
}
trap cleanup EXIT

send_message() {
  local text="$1"
  local telegram_id="$2"
  local update_id="$3"
  local payload
  payload="$(python3 -c "
import json, sys
print(json.dumps({
  'update': {
    'update_id': int(sys.argv[1]),
    'message': {
      'message_id': int(sys.argv[1]),
      'from': {'id': int(sys.argv[2]), 'language_code': 'en'},
      'chat': {'id': -int(sys.argv[2])},
      'text': sys.argv[3],
      'message_thread_id': None
    }
  },
  'source': 'admin-queue-test'
}))
" "$update_id" "$telegram_id" "$text")"
  bash scripts/proxy-curl.sh /webhook/admin-queue-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "aqtestentry00001",
  "name": "admin-queue-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "admin-queue-test", "responseMode": "responseNode", "options": {}},
     "id": "x0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "admin-queue-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "x0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "x0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "x0000000-0000-4000-8000-000000000003", "name": "Respond",
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
docker compose cp "$TMP" n8n:/tmp/admin-queue-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/admin-queue-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=aqtestentry00001 >/dev/null
$COMPOSE restart n8n >/dev/null
for i in $(seq 1 20); do
  h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done
rm -f "$TMP"

# A member asking does not drain the queue -- only an admin's "confirm
# all" actually applies (R20 is explicitly an admin capability).
send_message "confirm all" "$MEMBER_TG" $(( RANDOM + 100000000 ))
sleep 1
member_attempt_state="$(psql_meowhub -t -A -c "select confirmation_state from transaction where id = ${TXN_A};")"
if [ "$member_attempt_state" = "unconfirmed" ]; then
  echo "PASS: a non-admin's 'confirm all' does not drain the queue"
else
  echo "FAILED: expected the queue untouched by a non-admin, got '${member_attempt_state}'"
  fail=1
fi

# A43: an admin lists and confirms the whole queue in one reply.
send_message "unconfirmed" "$ADMIN_TG" $(( RANDOM + 150000000 ))
sleep 1
send_message "confirm all" "$ADMIN_TG" $(( RANDOM + 200000000 ))
sleep 1
state_a="$(psql_meowhub -t -A -c "select confirmation_state || '|' || confirmation_route from transaction where id = ${TXN_A};")"
state_b="$(psql_meowhub -t -A -c "select confirmation_state || '|' || confirmation_route from transaction where id = ${TXN_B};")"
if [ "$state_a" = "confirmed|review" ] && [ "$state_b" = "confirmed|review" ]; then
  echo "PASS: an admin lists and confirms the whole queue in one reply (A43)"
else
  echo "FAILED: expected both transactions confirmed via review, got a='${state_a}' b='${state_b}'"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='aqtestentry00001'; delete from webhook_entity where \"workflowId\"='aqtestentry00001';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
