#!/usr/bin/env bash
# Proves spec 0003 T10's A3: an admin can open an account or merge two
# categories by talking to the bot, outside the setup flow -- restated
# before it is applied, and the audit row names the admin as the actor
# (ADR 0042). A4's non-admin refusal is already proven for setup;
# this proves the same database-level guarantee holds for a
# structural change requested any other time.
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
TELEGRAM_ID=$(( RANDOM + 600000000 ))
NONADMIN_TELEGRAM_ID=$(( RANDOM + 650000000 ))

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
  insert into member_channel (member_id, kind, external_id, linked_by) values (${ADMIN_ID}, 'telegram', '${TELEGRAM_ID}', ${ADMIN_ID});
  insert into member_channel (member_id, kind, external_id, linked_by) values (${MEMBER_ID}, 'telegram', '${NONADMIN_TELEGRAM_ID}', ${ADMIN_ID});
" >/dev/null

# Each statement is its own transaction (-f, not -c): one failure here
# must not silently roll back the others, which is how the fixture
# account survived earlier runs and then failed the *next* run's first
# assertion -- and test-capture-text's A31, which asks about "savings"
# precisely because the household has none.
remove_fixtures() {
  psql_meowhub -v ON_ERROR_STOP=0 -f /dev/stdin >/dev/null 2>&1 <<'SQL' || true
select set_config('meowhub.actor', 'test-suite', false);
update member set default_payment_account_id = null
  where default_payment_account_id in (select id from account where name = 'Savings');
delete from capture where transaction_id in (
  select distinct p.transaction_id from posting p join account a on a.id = p.account_id where a.name = 'Savings');
delete from posting where transaction_id in (
  select distinct p.transaction_id from posting p join account a on a.id = p.account_id where a.name = 'Savings');
delete from transaction where id not in (select transaction_id from posting);
delete from account where name = 'Savings';
SQL
}

# Debris from an interrupted earlier run would fail this test's own
# first assertion, so it is cleared before anything is asserted.
remove_fixtures

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    delete from capture where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from conversation where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from member_channel where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from member where id in (${ADMIN_ID}, ${MEMBER_ID});
  " >/dev/null 2>&1 || true
  remove_fixtures
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
  'source': 'structural-test'
}))
" "$update_id" "$telegram_id" "$text")"
  bash scripts/proxy-curl.sh /webhook/structural-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "structtestentry1",
  "name": "structural-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "structural-test", "responseMode": "responseNode", "options": {}},
     "id": "t0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "structural-test"},
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
docker compose cp "$TMP" n8n:/tmp/structural-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/structural-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=structtestentry1 >/dev/null
$COMPOSE restart n8n >/dev/null
bash scripts/wait-for-n8n.sh
rm -f "$TMP"

# A4-equivalent: a non-admin's structural request creates no account.
send_message "open a Savings account" "$NONADMIN_TELEGRAM_ID" $(( RANDOM + 100000000 ))
sleep 1
send_message "yes" "$NONADMIN_TELEGRAM_ID" $(( RANDOM + 150000000 ))
sleep 1
nonadmin_created="$(psql_meowhub -t -A -c "select count(*) from account where name = 'Savings';")"
if [ "$nonadmin_created" = "0" ]; then
  echo "PASS: a non-admin's structural request outside setup creates nothing"
else
  echo "FAILED: expected no account created for a non-admin's request, found ${nonadmin_created}"
  fail=1
fi

# A3: an admin's structural request, restated then agreed, is applied
# and attributed to the admin.
send_message "open a Savings account" "$TELEGRAM_ID" $(( RANDOM + 200000000 ))
sleep 1
# R0b asks that the change be restated before it is applied. The old
# workflow held the proposal in a conversation payload; the agent says
# it, so the restatement is the reply -- and nothing exists yet.
restated="$(psql_meowhub -t -A -c "select raw_text from capture where member_id = ${ADMIN_ID} and direction = 'outbound' order by id desc limit 1;")"
not_yet_created="$(psql_meowhub -t -A -c "select count(*) from account where name = 'Savings';")"
if echo "$restated" | grep -qF "Savings" && [ "$not_yet_created" = "0" ]; then
  echo "PASS: the proposed change is restated, and nothing is applied until it is agreed (A3, R0b)"
else
  echo "FAILED: expected a restatement naming 'Savings' with no account yet, got reply='${restated}' accounts=${not_yet_created}"
  fail=1
fi

send_message "yes, that's right" "$TELEGRAM_ID" $(( RANDOM + 250000000 ))
sleep 1

account_row="$(psql_meowhub -t -A -c "select id, type from account where name = 'Savings';")"
account_id="$(echo "$account_row" | cut -d'|' -f1)"
account_type="$(echo "$account_row" | cut -d'|' -f2)"
if [ "$account_type" = "asset" ]; then
  echo "PASS: the account is applied with the type described (A3)"
else
  echo "FAILED: expected a Savings asset account, got type='${account_type}'"
  fail=1
fi

actor="$(psql_meowhub -t -A -c "select actor from audit_log where table_name = 'account' and row_id = '${account_id}' order by id desc limit 1;")"
if [ "$actor" = "$ADMIN_ID" ]; then
  echo "PASS: the audit row names the admin as the actor (A3)"
else
  echo "FAILED: expected audit actor '${ADMIN_ID}', got '${actor}'"
  fail=1
fi

conv_open="$(psql_meowhub -t -A -c "select count(*) from conversation where member_id = ${ADMIN_ID} and closed_at is null;")"
if [ "$conv_open" = "0" ]; then
  echo "PASS: nothing is left waiting once the change is applied"
else
  echo "FAILED: expected no exchange left open, got ${conv_open}"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='structtestentry1'; delete from webhook_entity where \"workflowId\"='structtestentry1';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
