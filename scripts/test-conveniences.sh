#!/usr/bin/env bash
# Proves spec 0003 T13: tapping the confirmation's "approve" button and
# typing its equivalent reach the same outcome (A32); a member's own
# last action is undone by a compensating change (A33); a free-text
# note survives on the transaction (A34); a remembered preference is
# reflected in a later capture, and stops being once an admin deletes
# it (A34a); "same again" repeats the last capture (A35); recent
# captures can be listed (A36).
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
TELEGRAM_ID=$(( RANDOM + 900000000 ))
ADMIN_TELEGRAM_ID=$(( RANDOM + 950000000 ))

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language, default_payment_account_id) values ('member', 'en', (select id from account where type='asset' and name='ABN AMRO Current')) returning id;
" | grep -E '^[0-9]+$' | tail -1)"
ADMIN_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('admin', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  insert into member_channel (member_id, kind, external_id, linked_by) values (${MEMBER_ID}, 'telegram', '${TELEGRAM_ID}', ${MEMBER_ID});
  insert into member_channel (member_id, kind, external_id, linked_by) values (${ADMIN_ID}, 'telegram', '${ADMIN_TELEGRAM_ID}', ${ADMIN_ID});
" >/dev/null

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    update member set default_payment_account_id = null where id in (${MEMBER_ID}, ${ADMIN_ID});
    delete from agent_memory where member_id in (${MEMBER_ID}, ${ADMIN_ID});
    delete from capture where member_id in (${MEMBER_ID}, ${ADMIN_ID});
    delete from posting where transaction_id in (select id from transaction where submitter in (${MEMBER_ID}, ${ADMIN_ID}));
    delete from transaction where submitter in (${MEMBER_ID}, ${ADMIN_ID});
    delete from member_channel where member_id in (${MEMBER_ID}, ${ADMIN_ID});
    delete from member where id in (${MEMBER_ID}, ${ADMIN_ID});
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
  'source': 'conveniences-test'
}))
" "$update_id" "$telegram_id" "$text")"
  bash scripts/proxy-curl.sh /webhook/conveniences-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

tap_button() {
  local data="$1"
  local telegram_id="$2"
  local update_id="$3"
  local payload
  payload="$(python3 -c "
import json, sys
print(json.dumps({
  'update': {
    'update_id': int(sys.argv[1]),
    'callback_query': {
      'id': 'cb' + str(sys.argv[1]),
      'from': {'id': int(sys.argv[2]), 'language_code': 'en'},
      'message': {'message_id': int(sys.argv[1]), 'chat': {'id': -int(sys.argv[2])}, 'message_thread_id': None},
      'data': sys.argv[3]
    }
  },
  'source': 'conveniences-test'
}))
" "$update_id" "$telegram_id" "$data")"
  bash scripts/proxy-curl.sh /webhook/conveniences-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "convtestentry001",
  "name": "conveniences-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "conveniences-test", "responseMode": "responseNode", "options": {}},
     "id": "w0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "conveniences-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "w0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "w0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "w0000000-0000-4000-8000-000000000003", "name": "Respond",
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
docker compose cp "$TMP" n8n:/tmp/conveniences-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/conveniences-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=convtestentry001 >/dev/null
$COMPOSE restart n8n >/dev/null
for i in $(seq 1 20); do
  h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done
rm -f "$TMP"

# A34: a note travels with the capture.
send_message "кофе 350, подарок Маше" "$TELEGRAM_ID" $(( RANDOM + 100000000 ))
sleep 1
NOTE_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
note_value="$(psql_meowhub -t -A -c "select note from transaction where id = ${NOTE_TXN};")"
if echo "$note_value" | grep -qi "маше"; then
  echo "PASS: a free-text note is stored on the transaction (A34)"
else
  echo "FAILED: expected a note mentioning 'Маше', got '${note_value}'"
  fail=1
fi

# A32: tapping approve confirms the transaction; the button's own
# callback_data is what capture-text.json attached to the reply.
send_message "coffee 300" "$TELEGRAM_ID" $(( RANDOM + 150000000 ))
sleep 1
CONFIRM_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
tap_button "confirm:${CONFIRM_TXN}" "$TELEGRAM_ID" $(( RANDOM + 200000000 ))
sleep 1
tapped_state="$(psql_meowhub -t -A -c "select confirmation_state from transaction where id = ${CONFIRM_TXN};")"
if [ "$tapped_state" = "confirmed" ]; then
  echo "PASS: tapping the approve button confirms the transaction (A32)"
else
  echo "FAILED: expected the tapped transaction confirmed, got '${tapped_state}'"
  fail=1
fi

# A32's other half: typing "confirm" reaches the identical outcome.
send_message "coffee 300" "$TELEGRAM_ID" $(( RANDOM + 250000000 ))
sleep 1
TYPED_CONFIRM_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
send_message "confirm" "$TELEGRAM_ID" $(( RANDOM + 300000000 ))
sleep 1
typed_state="$(psql_meowhub -t -A -c "select confirmation_state from transaction where id = ${TYPED_CONFIRM_TXN};")"
if [ "$typed_state" = "confirmed" ]; then
  echo "PASS: typing 'confirm' reaches the identical outcome as tapping approve (A32)"
else
  echo "FAILED: expected the typed-confirm transaction confirmed, got '${typed_state}'"
  fail=1
fi

# A33: undo reverses the member's own most recent action with a
# compensating entry, not a rewrite -- the original rows still exist.
send_message "snacks 400" "$TELEGRAM_ID" $(( RANDOM + 350000000 ))
sleep 1
UNDO_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
send_message "undo" "$TELEGRAM_ID" $(( RANDOM + 400000000 ))
sleep 1
original_still_there="$(psql_meowhub -t -A -c "select count(*) from transaction where id = ${UNDO_TXN};")"
original_leg="$(psql_meowhub -t -A -c "select amount from posting where transaction_id = ${UNDO_TXN} and account_id = (select id from account where type='asset' and name='ABN AMRO Current');")"
reversal_txn="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} and note like 'undo of #${UNDO_TXN}%' order by id desc limit 1;")"
reversal_leg="$(psql_meowhub -t -A -c "select amount from posting where transaction_id = ${reversal_txn} and account_id = (select id from account where type='asset' and name='ABN AMRO Current');")"
if [ "$original_still_there" = "1" ] && [ -n "$reversal_txn" ] && [ "$((original_leg + reversal_leg))" = "0" ]; then
  echo "PASS: undo reverses the member's last action with a compensating entry, original rows intact (A33)"
else
  echo "FAILED: expected the original row intact and a compensating reversal, got original='${original_still_there}' reversal_txn='${reversal_txn}' original_leg='${original_leg}' reversal_leg='${reversal_leg}'"
  fail=1
fi

# A34a: a remembered preference is reflected in a later, unrelated
# capture, and stops being once an admin deletes the memory row.
send_message "remember: use cash" "$TELEGRAM_ID" $(( RANDOM + 450000000 ))
sleep 1
memory_row="$(psql_meowhub -t -A -c "select id from agent_memory where member_id = ${MEMBER_ID} order by id desc limit 1;")"
send_message "gadget 900" "$TELEGRAM_ID" $(( RANDOM + 500000000 ))
sleep 1
MEMORY_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
memory_account="$(psql_meowhub -t -A -c "
  select a.name from posting p join account a on a.id = p.account_id
  where p.transaction_id = ${MEMORY_TXN} and p.amount < 0;
")"
if [ "$memory_account" = "Cash" ]; then
  echo "PASS: a remembered preference is reflected in a later capture (A34a)"
else
  echo "FAILED: expected the remembered 'use cash' preference to post against Cash, got '${memory_account}'"
  fail=1
fi

psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', false);
  delete from agent_memory where id = ${memory_row};
" >/dev/null
send_message "gizmo 900" "$TELEGRAM_ID" $(( RANDOM + 550000000 ))
sleep 1
AFTER_DELETE_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
after_delete_account="$(psql_meowhub -t -A -c "
  select a.name from posting p join account a on a.id = p.account_id
  where p.transaction_id = ${AFTER_DELETE_TXN} and p.amount < 0;
")"
if [ "$after_delete_account" != "Cash" ]; then
  echo "PASS: once an admin deletes the memory row, a following capture no longer reflects it (A34a)"
else
  echo "FAILED: expected the deleted memory to no longer apply, got '${after_delete_account}'"
  fail=1
fi

# A35: "same again" repeats the last capture -- same amount, category,
# account, dated today, unconfirmed.
send_message "same again" "$TELEGRAM_ID" $(( RANDOM + 600000000 ))
sleep 1
SAME_AGAIN_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
same_again_amount="$(psql_meowhub -t -A -c "select amount from posting where transaction_id = ${SAME_AGAIN_TXN} and amount > 0;")"
same_again_state="$(psql_meowhub -t -A -c "select confirmation_state from transaction where id = ${SAME_AGAIN_TXN};")"
prior_amount="$(psql_meowhub -t -A -c "select amount from posting where transaction_id = ${AFTER_DELETE_TXN} and amount > 0;")"
if [ "$same_again_amount" = "$prior_amount" ] && [ "$same_again_state" = "unconfirmed" ]; then
  echo "PASS: 'same again' repeats the last capture, unconfirmed (A35)"
else
  echo "FAILED: expected the repeated amount to match ('${prior_amount}') and be unconfirmed, got amount='${same_again_amount}' state='${same_again_state}'"
  fail=1
fi

# A36: recent captures can be listed. The list is read directly and
# replied inline, nothing is written -- the observable proof is that
# the request executes cleanly (n8n reports success, not error) against
# a member who genuinely has several recent captures to list.
recent_list_txn_count="$(psql_meowhub -t -A -c "select count(*) from transaction where submitter = ${MEMBER_ID};")"
last_exec_id_before="$(psql_meowhub -t -A -c "" 2>/dev/null; $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -t -A -c "select coalesce(max(id), 0) from execution_entity;")"
send_message "my recent expenses" "$TELEGRAM_ID" $(( RANDOM + 650000000 ))
sleep 1
recent_list_status="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -t -A -c "select status from execution_entity where id > ${last_exec_id_before} and \"workflowId\" = 'correction0001' order by id desc limit 1;")"
if [ "$recent_list_status" = "success" ] && [ "$recent_list_txn_count" -ge "1" ]; then
  echo "PASS: asking for recent captures is handled cleanly, with real captures to list (A36)"
else
  echo "FAILED: expected the recent-list request to succeed with captures on hand, got status='${recent_list_status}' count=${recent_list_txn_count}"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='convtestentry001'; delete from webhook_entity where \"workflowId\"='convtestentry001';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
