#!/usr/bin/env bash
# Proves spec 0003 T10's done-when for real: an admin sets the books up
# by talking to the bot — accounts, opening balances, household
# settings, a default payment account — driven through the real
# dispatch workflow and the real (stubbed) model gateway.
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

# Debris from an interrupted prior run (this script itself, or a
# manual test during development) is cleaned unconditionally before a
# new run starts, by fixture account name rather than by member id --
# a fresh run's own ids can never collide with an old run's, so a
# leftover FK from an old run silently defeated the id-scoped cleanup
# below. Each statement runs as its own transaction (-f, not -c) so
# one FK error here does not roll back the others.
psql_meowhub -v ON_ERROR_STOP=0 -f /dev/stdin >/dev/null 2>&1 <<'SQL' || true
select set_config('meowhub.actor', 'test-suite', false);
update member set default_payment_account_id = null
  where default_payment_account_id in (select id from account where name in ('ABN AMRO checking', 'ICS credit card', 'ABN AMRO savings'));
delete from capture where transaction_id in (
  select distinct p.transaction_id from posting p join account a on a.id = p.account_id
  where a.name in ('ABN AMRO checking', 'ICS credit card', 'ABN AMRO savings')
);
delete from posting where transaction_id in (
  select distinct p.transaction_id from posting p join account a on a.id = p.account_id
  where a.name in ('ABN AMRO checking', 'ICS credit card', 'ABN AMRO savings')
);
delete from transaction where id in (
  select t.id from transaction t left join posting p on p.transaction_id = t.id where p.id is null
);
alter table account_term disable trigger account_term_deny_delete;
delete from account_term where account_id in (select id from account where name in ('ABN AMRO checking', 'ICS credit card', 'ABN AMRO savings'));
alter table account_term enable trigger account_term_deny_delete;
delete from account where name in ('ABN AMRO checking', 'ICS credit card', 'ABN AMRO savings');
SQL

fail=0
TELEGRAM_ID=$(( RANDOM + 500000000 ))
NONADMIN_TELEGRAM_ID=$(( RANDOM + 550000000 ))

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

cleanup() {
  # Order matters: a member's default_payment_account_id must be
  # cleared before the account it points to is deleted, or the whole
  # implicit transaction this -c string runs as aborts and rolls back
  # every delete in it silently (a real bug found running this test
  # repeatedly -- debris from an aborted cleanup masqueraded as a
  # regression in the next run).
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    update member set default_payment_account_id = null where id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from capture where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from posting where transaction_id in (select id from transaction where submitter in (${ADMIN_ID}, ${MEMBER_ID}));
    delete from transaction where submitter in (${ADMIN_ID}, ${MEMBER_ID});
    delete from conversation where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from member_channel where member_id in (${ADMIN_ID}, ${MEMBER_ID});
    delete from account where name in ('ABN AMRO checking', 'ICS credit card');
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
  'source': 'setup-test'
}))
" "$update_id" "$telegram_id" "$text")"
  bash scripts/proxy-curl.sh /webhook/setup-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "setuptestentry01",
  "name": "setup-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "setup-test", "responseMode": "responseNode", "options": {}},
     "id": "h0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "setup-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "h0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "h0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "h0000000-0000-4000-8000-000000000003", "name": "Respond",
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
docker compose cp "$TMP" n8n:/tmp/setup-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/setup-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=setuptestentry01 >/dev/null
$COMPOSE restart n8n >/dev/null
for i in $(seq 1 20); do
  h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done
rm -f "$TMP"

# A4: a non-admin's structural request creates nothing, fails at the database.
send_message "let's set up the accounts" "$NONADMIN_TELEGRAM_ID" $(( RANDOM + 100000000 ))
sleep 1
nonadmin_conv="$(psql_meowhub -t -A -c "select count(*) from conversation where member_id = ${MEMBER_ID} and kind = 'setup';")"
if [ "$nonadmin_conv" = "0" ]; then
  echo "PASS: a non-admin's attempt to start setup creates nothing (A4)"
else
  echo "FAILED: expected no setup conversation for a non-admin, found ${nonadmin_conv}"
  fail=1
fi

# A1: the full interview — two accounts, settings, default account —
# ends with real accounts at the opening balances stated.
send_message "let's set up the accounts" "$TELEGRAM_ID" $(( RANDOM + 150000000 ))
sleep 1
send_message "ABN AMRO checking, has 3500 in it" "$TELEGRAM_ID" $(( RANDOM + 200000000 ))
sleep 1
send_message "ICS credit card, I owe 450 on it, limit is 3000" "$TELEGRAM_ID" $(( RANDOM + 250000000 ))
sleep 1
send_message "that's all" "$TELEGRAM_ID" $(( RANDOM + 300000000 ))
sleep 1
send_message "we're in Amsterdam, euros" "$TELEGRAM_ID" $(( RANDOM + 350000000 ))
sleep 1
send_message "ABN AMRO checking" "$TELEGRAM_ID" $(( RANDOM + 400000000 ))
sleep 1

abn_balance="$(psql_meowhub -t -A -c "select balance from v_account_balance where name = 'ABN AMRO checking';")"
if [ "$abn_balance" = "3500" ]; then
  echo "PASS: the asset account's balance equals the stated opening balance (A1)"
else
  echo "FAILED: expected ABN AMRO checking balance 3500, got '${abn_balance}'"
  fail=1
fi

card_balance="$(psql_meowhub -t -A -c "select balance from v_account_balance where name = 'ICS credit card';")"
if [ "$card_balance" = "450" ]; then
  echo "PASS: the liability account shows 450 owed, the conventional sign (A1)"
else
  echo "FAILED: expected ICS credit card balance 450 owed, got '${card_balance}'"
  fail=1
fi

conv_closed="$(psql_meowhub -t -A -c "select count(*) from conversation where member_id = ${ADMIN_ID} and kind = 'setup' and closed_at is not null;")"
default_acct="$(psql_meowhub -t -A -c "select a.name from member m join account a on a.id = m.default_payment_account_id where m.id = ${ADMIN_ID};")"
if [ "$conv_closed" = "1" ] && [ "$default_acct" = "ABN AMRO checking" ]; then
  echo "PASS: the interview closes and the default payment account is set (A1)"
else
  echo "FAILED: expected the conversation closed and default account 'ABN AMRO checking', got closed=${conv_closed} default='${default_acct}'"
  fail=1
fi

# A2: capture already works after setup, using the new default account.
send_message "coffee 350" "$TELEGRAM_ID" $(( RANDOM + 450000000 ))
sleep 1
capture_txn="$(psql_meowhub -t -A -c "
  select count(*) from transaction t join posting p on p.transaction_id = t.id
  where t.submitter = ${ADMIN_ID} and p.account_id = (select id from account where name = 'ABN AMRO checking') and p.amount = -350;
")"
if [ "$capture_txn" = "1" ]; then
  echo "PASS: capture works immediately after setup, against the account just configured (A2)"
else
  echo "FAILED: expected a capture posted against the new default account, got count=${capture_txn}"
  fail=1
fi

# A38: "what still needs setting up" on a paused conversation.
send_message "let's set up the accounts" "$TELEGRAM_ID" $(( RANDOM + 500000000 ))
sleep 1
send_message "what's left to set up?" "$TELEGRAM_ID" $(( RANDOM + 550000000 ))
sleep 1
paused_conv="$(psql_meowhub -t -A -c "select id from conversation where member_id = ${ADMIN_ID} and kind = 'setup' and closed_at is null order by id desc limit 1;")"
paused_step="$(psql_meowhub -t -A -c "select step from conversation where id = ${paused_conv};")"
if [ -n "$paused_conv" ] && [ "$paused_step" = "accounts" ]; then
  echo "PASS: asking what remains does not advance the paused conversation (A38)"
else
  echo "FAILED: expected the conversation still open on step 'accounts', got conv='${paused_conv}' step='${paused_step}'"
  fail=1
fi

# A39: the same paused conversation survives a real restart of both
# n8n (the workflow engine) and postgres (the system of record) --
# proving its state lives in the database (ADR 0038), not in an
# execution context that a restart would wipe.
$COMPOSE restart n8n postgres >/dev/null
for i in $(seq 1 30); do
  n8n_h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  pg_h="$($COMPOSE ps postgres --format '{{.Health}}' 2>/dev/null)"
  [ "$n8n_h" = "healthy" ] && [ "$pg_h" = "healthy" ] && break
  sleep 2
done

resumed_step="$(psql_meowhub -t -A -c "select step from conversation where id = ${paused_conv};")"
send_message "ABN AMRO savings, has 100 in it" "$TELEGRAM_ID" $(( RANDOM + 560000000 ))
sleep 1
resumed_after_message="$(psql_meowhub -t -A -c "select count(*) from conversation where id = ${paused_conv} and closed_at is null;")"
resumed_account="$(psql_meowhub -t -A -c "select count(*) from account where name = 'ABN AMRO savings';")"
if [ "$resumed_step" = "accounts" ] && [ "$resumed_after_message" = "1" ] && [ "$resumed_account" = "1" ]; then
  echo "PASS: the paused conversation resumes at the same step after a container restart (A39)"
else
  echo "FAILED: expected the same conversation to resume on step 'accounts' and accept the next answer, got step='${resumed_step}' still_open='${resumed_after_message}' account_created='${resumed_account}'"
  fail=1
fi

psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  delete from account where name = 'ABN AMRO savings';
  delete from conversation where id = ${paused_conv};
" >/dev/null 2>&1 || true

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='setuptestentry01'; delete from webhook_entity where \"workflowId\"='setuptestentry01';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
