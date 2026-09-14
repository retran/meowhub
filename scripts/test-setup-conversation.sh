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
    delete from member where id in (${ADMIN_ID}, ${MEMBER_ID});
  " >/dev/null 2>&1 || true
  # The fixture accounts go last and by the same FK-respecting route the
  # pre-flight uses. A39's account carries an opening balance, so
  # deleting the account on its own always failed on the posting
  # foreign key -- silently, under `|| true` -- and left "ABN AMRO
  # savings" behind for the next suite. test-capture-text's A31 asks
  # about "savings" precisely because the household has no such
  # account, so this test's leftovers were failing that one.
  psql_meowhub -v ON_ERROR_STOP=0 -f /dev/stdin >/dev/null 2>&1 <<'SQL' || true
select set_config('meowhub.actor', 'test-suite', false);
-- A38 deletes the household timezone to make the setup genuinely
-- half-finished. Put it back: without it v_reporting_period has no
-- rows, so every spend view is empty and the next suite's figures
-- vanish (ADR 0045).
insert into household_setting (key, value, updated_by)
select 'timezone', '"Europe/Amsterdam"', (select id from member where role = 'admin' order by id limit 1)
where not exists (select 1 from household_setting where key = 'timezone');
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
bash scripts/wait-for-n8n.sh
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

# The interview is over when nothing is left waiting for an answer.
# The old step machine recorded that as a closed conversation of kind
# 'setup'; the agent records it as an exchange no longer open, which is
# the same fact about the same table without asserting a step column
# that no longer exists (ADR 0046).
conv_open="$(psql_meowhub -t -A -c "select count(*) from conversation where member_id = ${ADMIN_ID} and closed_at is null;")"
default_acct="$(psql_meowhub -t -A -c "select a.name from member m join account a on a.id = m.default_payment_account_id where m.id = ${ADMIN_ID};")"
if [ "$conv_open" = "0" ] && [ "$default_acct" = "ABN AMRO checking" ]; then
  echo "PASS: the interview closes and the default payment account is set (A1)"
else
  echo "FAILED: expected nothing left waiting and default account 'ABN AMRO checking', got open=${conv_open} default='${default_acct}'"
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

# A38: "what still needs setting up", genuinely half-finished. The old
# step machine called a fresh conversation "halfway" because its step
# column started at the beginning; the agent reads the books, so the
# state has to actually be half-finished for the question to have an
# answer. Removing the household timezone is what makes it so.
psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', false);
  delete from household_setting where key = 'timezone';
" >/dev/null
accounts_before_asking="$(psql_meowhub -t -A -c "select count(*) from account;")"
send_message "let's set up the accounts" "$TELEGRAM_ID" $(( RANDOM + 500000000 ))
sleep 1
send_message "what's left to set up?" "$TELEGRAM_ID" $(( RANDOM + 550000000 ))
sleep 1
# R29 asks that the remaining steps be reported; A38 asks that
# reporting them advances nothing. The old step machine expressed both
# as a `step` column; the agent has no steps, so this asserts the two
# things the requirement actually promises -- the exchange is still
# open, and the reply names what is left without creating anything.
paused_conv="$(psql_meowhub -t -A -c "select id from conversation where member_id = ${ADMIN_ID} and closed_at is null order by id desc limit 1;")"
accounts_after_asking="$(psql_meowhub -t -A -c "select count(*) from account;")"
whats_left_reply="$(psql_meowhub -t -A -c "select raw_text from capture where member_id = ${ADMIN_ID} and direction = 'outbound' order by id desc limit 1;")"
if [ -n "$paused_conv" ] && [ "$accounts_after_asking" = "$accounts_before_asking" ] && echo "$whats_left_reply" | grep -qiE "still to do|timezone|default"; then
  echo "PASS: asking what remains reports it and advances nothing (A38, R29)"
else
  echo "FAILED: expected an open exchange, no new account, and a reply naming what is left; got conv='${paused_conv}' accounts=${accounts_after_asking} (was ${accounts_before_asking}) reply='${whats_left_reply}'"
  fail=1
fi

# A39: the same paused conversation survives a real restart of both
# n8n (the workflow engine) and postgres (the system of record) --
# proving its state lives in the database (ADR 0038), not in an
# execution context that a restart would wipe.
$COMPOSE restart n8n postgres >/dev/null
bash scripts/wait-for-n8n.sh

# R0e's claim is that the state is in PostgreSQL, so a restart loses
# nothing. What proves it is that the same exchange is still there
# afterwards, with its messages intact, and that the next answer is
# understood in its context -- not that a `step` column survived.
resumed_messages="$(psql_meowhub -t -A -c "select count(*) from capture where conversation_id = ${paused_conv};")"
send_message "ABN AMRO savings, has 100 in it" "$TELEGRAM_ID" $(( RANDOM + 560000000 ))
sleep 1
resumed_after_message="$(psql_meowhub -t -A -c "select count(*) from conversation where id = ${paused_conv} and closed_at is null;")"
resumed_account="$(psql_meowhub -t -A -c "select count(*) from account where name = 'ABN AMRO savings';")"
if [ "$resumed_messages" -ge "2" ] && [ "$resumed_after_message" = "1" ] && [ "$resumed_account" = "1" ]; then
  echo "PASS: the paused exchange survives a container restart and the next answer lands in it (A39)"
else
  echo "FAILED: expected the exchange intact after the restart and the next answer accepted, got messages=${resumed_messages} still_open='${resumed_after_message}' account_created='${resumed_account}'"
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
