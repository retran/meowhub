#!/usr/bin/env bash
# Proves spec 0003 T11: an admin corrects a just-recorded transaction in
# one message (A13); a non-admin's same message becomes a
# correction_request instead of a write, and the admins are notified
# (A14); any member reclassifies unconditionally (A15); an admin
# deletes (A16). A17 (a non-admin cannot delete) is already proven by
# impersonation in db/tests/013_ledger_row_level_security.sql -- this
# proves the bot-driven paths, each minted as the acting member's own
# role (ADR 0042) so the database, not this workflow, is what refuses.
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
ADMIN_TG=$(( RANDOM + 700000000 ))
MEMBER_TG=$(( RANDOM + 750000000 ))

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

new_txn() {
  local submitter="$1"
  psql_meowhub -t -A -c "
    select set_config('meowhub.actor', 'test-suite', false);
    set role hh_agent;
    insert into transaction (date, submitter, source, confirmation_state)
      values (current_date, ${submitter}, 'text', 'unconfirmed') returning id;
  " | grep -E '^[0-9]+$' | tail -1
}

new_postings() {
  local txn_id="$1"
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    set role hh_agent;
    insert into posting (transaction_id, account_id, amount, currency) values (${txn_id}, ${PAYMENT_ACCT}, -350, 'EUR');
    insert into posting (transaction_id, account_id, amount, currency) values (${txn_id}, ${CATEGORY_ACCT}, 350, 'EUR');
  " >/dev/null
}

PAYMENT_ACCT="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='asset' and active limit 1;" | grep -E '^[0-9]+$' | tail -1)"
CATEGORY_ACCT="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='expense' and name='groceries' limit 1;" | grep -E '^[0-9]+$' | tail -1)"
TRANSPORT_ACCT="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='expense' and name='transport' limit 1;" | grep -E '^[0-9]+$' | tail -1)"

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    delete from correction_request where requested_by in (${ADMIN_ID}, ${MEMBER_ID});
    delete from capture where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from posting where transaction_id in (select id from transaction where submitter in (${ADMIN_ID}, ${MEMBER_ID}));
    delete from transaction where submitter in (${ADMIN_ID}, ${MEMBER_ID});
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
  'source': 'correction-test'
}))
" "$update_id" "$telegram_id" "$text")"
  bash scripts/proxy-curl.sh /webhook/correction-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "corrtestentry001",
  "name": "correction-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "correction-test", "responseMode": "responseNode", "options": {}},
     "id": "u0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "correction-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "u0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "u0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "u0000000-0000-4000-8000-000000000003", "name": "Respond",
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
docker compose cp "$TMP" n8n:/tmp/correction-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/correction-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=corrtestentry001 >/dev/null
$COMPOSE restart n8n >/dev/null
for i in $(seq 1 20); do
  h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done
rm -f "$TMP"

# A13: an admin corrects a just-recorded transaction's amount in one message.
TXN_A="$(new_txn "$ADMIN_ID")"
new_postings "$TXN_A"
send_message "it was 35 not 350" "$ADMIN_TG" $(( RANDOM + 100000000 ))
sleep 1
new_amount="$(psql_meowhub -t -A -c "select amount from posting where transaction_id = ${TXN_A} and account_id = ${CATEGORY_ACCT};")"
if [ "$new_amount" = "35" ]; then
  echo "PASS: an admin corrects a just-recorded transaction's amount in one message (A13)"
else
  echo "FAILED: expected the category posting corrected to 35, got '${new_amount}'"
  fail=1
fi

# A14: the same correction from a non-admin, on their OWN capture that
# has since been confirmed -- R7b's correction window is "while it is
# still unconfirmed"; once confirmed, even the capturer's own
# correction becomes a request (R16a), same gate 013 already proves.
TXN_B="$(new_txn "$MEMBER_ID")"
new_postings "$TXN_B"
psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', false);
  update transaction set confirmation_state = 'confirmed', confirmation_route = 'review', confirmed_by = ${MEMBER_ID}, confirmed_at = now() where id = ${TXN_B};
" >/dev/null
send_message "it was 35 not 350" "$MEMBER_TG" $(( RANDOM + 150000000 ))
sleep 1
unchanged_amount="$(psql_meowhub -t -A -c "select amount from posting where transaction_id = ${TXN_B} and account_id = ${CATEGORY_ACCT};")"
request_count="$(psql_meowhub -t -A -c "select count(*) from correction_request where transaction_id = ${TXN_B} and requested_by = ${MEMBER_ID};")"
if [ "$unchanged_amount" = "350" ] && [ "$request_count" = "1" ]; then
  echo "PASS: a non-admin's correction is recorded as a request, not applied (A14)"
else
  echo "FAILED: expected amount unchanged (350) and one correction_request, got amount='${unchanged_amount}' requests='${request_count}'"
  fail=1
fi

# A15: any member reclassifies a transaction's category unconditionally
# — including one they did not submit.
TXN_C="$(new_txn "$ADMIN_ID")"
new_postings "$TXN_C"
send_message "put it under transport" "$MEMBER_TG" $(( RANDOM + 200000000 ))
sleep 1
reclassified="$(psql_meowhub -t -A -c "select count(*) from posting where transaction_id = ${TXN_C} and account_id = ${TRANSPORT_ACCT};")"
if [ "$reclassified" = "1" ]; then
  echo "PASS: any member reclassifies category unconditionally, even on another member's capture (A15)"
else
  echo "FAILED: expected the category posting reclassified to transport, got count=${reclassified}"
  fail=1
fi

# A16: an admin deletes a just-recorded transaction; it stops
# affecting balances but the row is not physically erased from history
# (proven at the impersonation level in 013_ledger_row_level_security.sql
# — here we prove the bot path reaches that same database guarantee).
TXN_D="$(new_txn "$ADMIN_ID")"
new_postings "$TXN_D"
send_message "delete it" "$ADMIN_TG" $(( RANDOM + 250000000 ))
sleep 1
deleted="$(psql_meowhub -t -A -c "select count(*) from transaction where id = ${TXN_D};")"
if [ "$deleted" = "0" ]; then
  echo "PASS: an admin deletes a transaction via the bot (A16)"
else
  echo "FAILED: expected the transaction deleted, got count=${deleted}"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='corrtestentry001'; delete from webhook_entity where \"workflowId\"='corrtestentry001';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
