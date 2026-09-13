#!/usr/bin/env bash
# Proves spec 0003 T8's done-when for real: a real member, linked and
# with a default payment account, writes "coffee 350" and the household's
# books gain a correct, balanced, attributed transaction (A7) — driven
# through the real dispatch workflow and the real (stubbed) model
# gateway, never asserted from the workflow's own logic.
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
TELEGRAM_ID=$(( RANDOM + 500000000 ))

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

ACCOUNT_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into account (type, name) values ('asset', 'Assets:CaptureTestBank') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  update member set default_payment_account_id = ${ACCOUNT_ID} where id = ${MEMBER_ID};
  insert into member_channel (member_id, kind, external_id, linked_by) values (${MEMBER_ID}, 'telegram', '${TELEGRAM_ID}', ${MEMBER_ID});
" >/dev/null

cleanup() {
  # Order matters (foreign keys): capture references transaction, so it
  # must go first; member must go before account (member holds the FK),
  # after member_channel (which references member).
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    delete from capture where member_id = ${MEMBER_ID};
    delete from posting where transaction_id in (select id from transaction where submitter = ${MEMBER_ID});
    delete from transaction where submitter = ${MEMBER_ID};
    delete from conversation where member_id = ${MEMBER_ID};
    delete from member_channel where member_id = ${MEMBER_ID} or linked_by = ${MEMBER_ID};
    delete from member where id = ${MEMBER_ID};
    delete from account where id = ${ACCOUNT_ID};
    delete from merchant_alias where merchant_id in (select id from merchant where name ilike '%pret%');
    delete from merchant where name ilike '%pret%';
    delete from account where name = 'Test Credit Card';
  " >/dev/null 2>&1 || true
}
trap cleanup EXIT

send_message() {
  local text="$1"
  local update_id="$2"
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
  'source': 'capture-test'
}))
" "$update_id" "$TELEGRAM_ID" "$text")"
  bash scripts/proxy-curl.sh /webhook/capture-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "capturetestentry1",
  "name": "capture-text-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "capture-test", "responseMode": "responseNode", "options": {}},
     "id": "f0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "capture-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "f0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "f0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "f0000000-0000-4000-8000-000000000003", "name": "Respond",
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
docker compose cp "$TMP" n8n:/tmp/capture-text-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/capture-text-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=capturetestentry1 >/dev/null
$COMPOSE restart n8n >/dev/null
for i in $(seq 1 20); do
  h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done
rm -f "$TMP"

send_message "coffee 350" $(( RANDOM + 100000000 ))
sleep 1

result="$(psql_meowhub -t -A -F'|' -c "
select p.account_id, p.amount, p.currency
from transaction t join posting p on p.transaction_id = t.id
where t.submitter = ${MEMBER_ID}
order by p.account_id;
")"
echo "postings: $result"

txn_count="$(psql_meowhub -t -A -c "select count(*) from transaction where submitter = ${MEMBER_ID};")"
if [ "$txn_count" = "1" ]; then
  echo "PASS: exactly one transaction recorded (A7)"
else
  echo "FAILED: expected exactly one transaction, got ${txn_count}"
  fail=1
fi

payment_amount="$(psql_meowhub -t -A -c "select p.amount from transaction t join posting p on p.transaction_id = t.id where t.submitter = ${MEMBER_ID} and p.account_id = ${ACCOUNT_ID};")"
if [ "$payment_amount" = "-350" ]; then
  echo "PASS: the payment account is reduced by 3.50 (A7)"
else
  echo "FAILED: expected payment posting -350, got ${payment_amount}"
  fail=1
fi

txn_date="$(psql_meowhub -t -A -c "select date from transaction where submitter = ${MEMBER_ID};")"
today="$(date -u +%Y-%m-%d)"
if [ "$txn_date" = "$today" ]; then
  echo "PASS: dated today (A7)"
else
  echo "FAILED: expected today (${today}), got ${txn_date}"
  fail=1
fi

# A8: a known merchant, decimal amount, case-insensitive alias match.
# Reuses whatever "groceries"/"Albert Heijn" already exist (the seed
# creates both) rather than assuming a fresh database.
GROCERIES_ID="$(psql_meowhub -t -A -c "select id from account where name = 'groceries' and type = 'expense' limit 1;")"
if [ -z "$GROCERIES_ID" ]; then
  GROCERIES_ID="$(psql_meowhub -t -A -c "
    select set_config('meowhub.actor', 'test-suite', true);
    insert into account (type, name) values ('expense', 'groceries') returning id;
  " | grep -E '^[0-9]+$' | tail -1)"
fi
AH_ID="$(psql_meowhub -t -A -c "select id from merchant where name = 'Albert Heijn' limit 1;")"
if [ -z "$AH_ID" ]; then
  AH_ID="$(psql_meowhub -t -A -c "
    select set_config('meowhub.actor', 'test-suite', true);
    insert into merchant (name, default_category_id) values ('Albert Heijn', ${GROCERIES_ID}) returning id;
  " | grep -E '^[0-9]+$' | tail -1)"
fi
if ! psql_meowhub -t -A -c "select 1 from merchant_alias where merchant_id = ${AH_ID} and lower(alias) = 'albert heijn';" | grep -q 1; then
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    insert into merchant_alias (merchant_id, alias) values (${AH_ID}, 'albert heijn');
  " >/dev/null
fi

send_message "groceries 24,40 albert heijn" $(( RANDOM + 200000000 ))
sleep 1

a8_amount="$(psql_meowhub -t -A -c "select p.amount from transaction t join posting p on p.transaction_id = t.id where t.submitter = ${MEMBER_ID} and t.merchant_id = ${AH_ID} and p.account_id = ${GROCERIES_ID};")"
if [ "$a8_amount" = "2440" ]; then
  echo "PASS: '24,40' is recorded as 24.40 and the merchant is matched by alias (A8)"
else
  echo "FAILED: expected 2440 recorded against the known merchant, got '${a8_amount}'"
  fail=1
fi

# A10: the SAME known merchant, no category stated — its own established
# default is used with no model call at all (the stub would only return
# 'dining' as its own fallback guess, never 'groceries', so this proves
# the merchant default was actually consulted, not the model).
send_message "24,40 albert heijn" $(( RANDOM + 300000000 ))
sleep 1

a10_category="$(psql_meowhub -t -A -c "
  select p.account_id from transaction t join posting p on p.transaction_id = t.id
  where t.submitter = ${MEMBER_ID} and t.merchant_id = ${AH_ID} and p.amount = 2440
  order by t.id desc limit 1;
")"
if [ "$a10_category" = "$GROCERIES_ID" ]; then
  echo "PASS: a known merchant's established category is used without a model guess (A10)"
else
  echo "FAILED: expected category ${GROCERIES_ID} (groceries) from the merchant default, got '${a10_category}'"
  fail=1
fi

# A9: an unseen merchant is created; a different spelling on a later
# capture resolves to the same merchant.
send_message "lunch 12 at Pret A Manger" $(( RANDOM + 400000000 ))
sleep 1
PRET_ID="$(psql_meowhub -t -A -c "select id from merchant where name ilike '%pret%' order by id desc limit 1;")"
if [ -n "$PRET_ID" ]; then
  echo "PASS: an unseen merchant is created (A9)"
else
  echo "FAILED: expected a new merchant to be created for 'Pret A Manger'"
  fail=1
fi
if ! psql_meowhub -t -A -c "select 1 from merchant_alias where merchant_id = ${PRET_ID} and lower(alias) = 'pret';" | grep -q 1; then
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    insert into merchant_alias (merchant_id, alias) values (${PRET_ID}, 'pret');
  " >/dev/null
fi

send_message "coffee 3 pret" $(( RANDOM + 450000000 ))
sleep 1
pret_txn_count="$(psql_meowhub -t -A -c "select count(*) from transaction where submitter = ${MEMBER_ID} and merchant_id = ${PRET_ID};")"
if [ "$pret_txn_count" = "2" ]; then
  echo "PASS: a later capture spelled differently resolves to the same merchant (A9)"
else
  echo "FAILED: expected both captures to resolve to merchant ${PRET_ID}, got ${pret_txn_count} matching transactions"
  fail=1
fi

# A11: a stated payment method resolves to that liability account, not
# the member's default payment account.
CARD_ID="$(psql_meowhub -t -A -c "select id from account where name ilike '%credit card%' and type = 'liability' limit 1;")"
if [ -z "$CARD_ID" ]; then
  CARD_ID="$(psql_meowhub -t -A -c "
    select set_config('meowhub.actor', 'test-suite', true);
    insert into account (type, name) values ('liability', 'Test Credit Card') returning id;
  " | grep -E '^[0-9]+$' | tail -1)"
fi

send_message "dinner 45 on the credit card" $(( RANDOM + 600000000 ))
sleep 1

a11_posting="$(psql_meowhub -t -A -c "
  select p.amount from transaction t join posting p on p.transaction_id = t.id
  where t.submitter = ${MEMBER_ID} and p.account_id = ${CARD_ID}
  order by t.id desc limit 1;
")"
default_touched="$(psql_meowhub -t -A -c "
  select count(*) from transaction t join posting p on p.transaction_id = t.id
  where t.submitter = ${MEMBER_ID} and p.account_id = ${ACCOUNT_ID} and p.amount = -45;
")"
if [ "$a11_posting" = "-45" ] && [ "$default_touched" = "0" ]; then
  echo "PASS: a stated payment method posts against that account, not the default (A11)"
else
  echo "FAILED: expected -45 against the credit card and nothing against the default account, got card=${a11_posting} default_matches=${default_touched}"
  fail=1
fi
# ---- T9: unparsed captures and the multi-question agent (R17) --------

# A18/A18a/A19/A40/A41: the full scripted multi-turn exchange in one go —
# unparsed, a question, an answer that still leaves a gap, a further
# *different* question, and a final answer that resolves it.
send_message "that was expensive" $(( RANDOM + 700000000 ))
sleep 1
conv_id="$(psql_meowhub -t -A -c "select id from conversation where member_id = ${MEMBER_ID} and closed_at is null order by id desc limit 1;")"
q1="$(psql_meowhub -t -A -c "select raw_text from capture where conversation_id = ${conv_id} and direction = 'outbound' order by sequence limit 1;")"
if [ -n "$conv_id" ] && [ "$q1" = "How much was it?" ]; then
  echo "PASS: no recoverable amount opens a conversation and asks one question (A18)"
else
  echo "FAILED: expected an open conversation asking 'How much was it?', got conv_id='${conv_id}' q1='${q1}'"
  fail=1
fi

send_message "at the shop" $(( RANDOM + 750000000 ))
sleep 1
q2="$(psql_meowhub -t -A -c "select raw_text from capture where conversation_id = ${conv_id} and direction = 'outbound' order by sequence desc limit 1;")"
still_open="$(psql_meowhub -t -A -c "select count(*) from conversation where id = ${conv_id} and closed_at is null;")"
if [ "$q2" != "$q1" ] && [ -n "$q2" ] && [ "$still_open" = "1" ]; then
  echo "PASS: an answer that still leaves a gap gets a further, different question (A18a)"
else
  echo "FAILED: expected a second, different question; got q1='${q1}' q2='${q2}' still_open=${still_open}"
  fail=1
fi

send_message "12 euros" $(( RANDOM + 800000000 ))
sleep 1
resolved_txn="$(psql_meowhub -t -A -c "
  select transaction_id from capture where conversation_id = ${conv_id} and state = 'resolved' limit 1;
")"
conv_closed="$(psql_meowhub -t -A -c "select count(*) from conversation where id = ${conv_id} and closed_at is not null;")"
message_count="$(psql_meowhub -t -A -c "select count(*) from capture where conversation_id = ${conv_id};")"
if [ -n "$resolved_txn" ] && [ "$conv_closed" = "1" ] && [ "$message_count" = "5" ]; then
  echo "PASS: a later answer resolves the capture, closes the conversation, and every message is stored (A19/A40)"
else
  echo "FAILED: expected a resolved transaction, a closed conversation, and 5 stored messages; got txn='${resolved_txn}' closed=${conv_closed} messages=${message_count}"
  fail=1
fi

# A41: running the same unresolved exchange again with no new information
# must not ask the same question a second time.
send_message "that was expensive" $(( RANDOM + 850000000 ))
sleep 1
conv_id2="$(psql_meowhub -t -A -c "select id from conversation where member_id = ${MEMBER_ID} and closed_at is null order by id desc limit 1;")"
send_message "that was expensive" $(( RANDOM + 860000000 ))
sleep 1
q_count="$(psql_meowhub -t -A -c "select count(*) from capture where conversation_id = ${conv_id2} and direction = 'outbound' and raw_text = 'How much was it?';")"
if [ "$q_count" = "1" ]; then
  echo "PASS: the same question is never asked twice without new information (A41)"
else
  echo "FAILED: expected exactly one outbound row for the repeated question, got ${q_count}"
  fail=1
fi
psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  delete from capture where conversation_id = ${conv_id2};
  delete from conversation where id = ${conv_id2};
" >/dev/null

# A20: the model gateway is unreachable — stored unparsed, told it will
# be handled, nothing recorded.
docker compose -f compose.yaml stop model-gateway-stub >/dev/null
send_message "coffee 5" $(( RANDOM + 900000000 ))
sleep 1
docker compose -f compose.yaml start model-gateway-stub >/dev/null
for i in $(seq 1 15); do
  h="$(docker compose -f compose.yaml ps model-gateway-stub --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 1
done
a20_state="$(psql_meowhub -t -A -c "select state from capture where member_id = ${MEMBER_ID} and raw_text = 'coffee 5' order by id desc limit 1;")"
if [ "$a20_state" = "unparsed" ]; then
  echo "PASS: a gateway failure is stored unparsed rather than lost (A20)"
else
  echo "FAILED: expected the capture stored unparsed when the gateway is unreachable, got state='${a20_state}'"
  fail=1
fi

# A28: the model returns a response violating the declared schema
# (missing inferred_fields) — treated as unparsed, nothing written.
send_message "SCHEMA_VIOLATION_TEST" $(( RANDOM + 950000000 ))
sleep 1
a28_state="$(psql_meowhub -t -A -c "select state from capture where member_id = ${MEMBER_ID} and raw_text = 'SCHEMA_VIOLATION_TEST' order by id desc limit 1;")"
if [ "$a28_state" = "unparsed" ]; then
  echo "PASS: a schema-violating model response is treated as unparsed, nothing written (A28)"
else
  echo "FAILED: expected the capture stored unparsed on a schema violation, got state='${a28_state}'"
  fail=1
fi

# A31: an invented account name is refused with a question, never a new account.
account_count_before="$(psql_meowhub -t -A -c "select count(*) from account;")"
send_message "coffee 3 from savings" $(( RANDOM + 970000000 ))
sleep 1
account_count_after="$(psql_meowhub -t -A -c "select count(*) from account;")"
a31_conv="$(psql_meowhub -t -A -c "select id from conversation where member_id = ${MEMBER_ID} and closed_at is null order by id desc limit 1;")"
if [ "$account_count_before" = "$account_count_after" ] && [ -n "$a31_conv" ]; then
  echo "PASS: an invented account name creates no account and asks a question instead (A31)"
else
  echo "FAILED: expected no new account and an open question, got before=${account_count_before} after=${account_count_after} conv='${a31_conv}'"
  fail=1
fi
psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  delete from capture where conversation_id = ${a31_conv};
  delete from conversation where id = ${a31_conv};
" >/dev/null 2>&1 || true

# cleanup the throwaway test-entry workflow (spec 0003, same rule as
# scripts/test-telegram-linking.sh's own cleanup).
$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='capturetestentry1'; delete from webhook_entity where \"workflowId\"='capturetestentry1';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
