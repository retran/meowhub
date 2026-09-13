#!/usr/bin/env bash
# Proves spec 0002 T12's done-when for real (ADR 0030, R6c/R6d):
#
# A18 — an unlinked Telegram id messages the bot: nothing is written to
#   member_channel, the attempt is logged, the reply reveals nothing.
# A19 — an admin links a Telegram id; a capture attributes to that member,
#   and survives a re-link to a different account unchanged. Uses the
#   real ledger (spec 0003 T1) directly, now that it exists.
# A20 — a member with no channel linked still reaches the app path. This
#   is already proven by scripts/test-proxy-path.sh, whose fixture member
#   never gets a member_channel row at all; not repeated here.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"
: "${PGRST_JWT_SECRET:?PGRST_JWT_SECRET not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: n8n is not running (run 'task up' first)"
  exit 0
fi

psql_meowhub() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" "$@"
}

fail=0

# ---- A18: an unlinked sender ------------------------------------------
UNLINKED_ID=$(( RANDOM + 800000000 ))
TMP="$(mktemp)"
cat > "$TMP" <<JSON
{
  "id": "linktestentry01",
  "name": "linking-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "linking-test", "responseMode": "responseNode", "options": {}},
     "id": "l0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "linking-test"},
    {"parameters": {"jsCode": "return [{ json: \$json.body }];"},
     "id": "l0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "l0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "l0000000-0000-4000-8000-000000000003", "name": "Respond",
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
docker compose cp "$TMP" n8n:/tmp/linking-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/linking-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=linktestentry01 >/dev/null
$COMPOSE restart n8n >/dev/null
for i in $(seq 1 20); do
  h="$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done
rm -f "$TMP"

UPDATE_ID=$(( RANDOM + 700000000 ))
PAYLOAD="{\"update\": {\"update_id\": ${UPDATE_ID}, \"message\": {\"from\": {\"id\": ${UNLINKED_ID}, \"language_code\": \"en\"}, \"chat\": {\"id\": -999}, \"text\": \"hello\", \"message_thread_id\": null}}, \"source\": \"linking-test\"}"
bash scripts/proxy-curl.sh /webhook/linking-test -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" >/dev/null || true

# cleanup the throwaway test-entry workflow regardless of outcome — left
# behind, it is undeclared drift the very next task:drift-schedule run
# would (rightly) catch (spec 0001 ADR 0010).
$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='linktestentry01'; delete from webhook_entity where \"workflowId\"='linktestentry01';" >/dev/null

denied_count="$(psql_meowhub -t -A -c "select count(*) from audit_log where table_name = 'member_channel' and operation = 'denied' and row_id = '${UNLINKED_ID}';")"
linked_count="$(psql_meowhub -t -A -c "select count(*) from member_channel where external_id = '${UNLINKED_ID}';")"

if [ "$denied_count" = "1" ] && [ "$linked_count" = "0" ]; then
  echo "PASS: an unlinked Telegram id writes nothing to member_channel; the attempt is logged (A18)"
else
  echo "FAILED: expected exactly one denied audit entry and no member_channel row, got denied=${denied_count} linked=${linked_count}"
  fail=1
fi

# ---- A19: link, capture, re-link, attribution unchanged ----------------
ADMIN_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
MEMBER_A="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
MEMBER_B="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

TELEGRAM_ID=$(( RANDOM + 600000000 ))

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    delete from posting where transaction_id = ${CAPTURE_ID:-0};
    delete from transaction where id = ${CAPTURE_ID:-0};
    delete from account where id in (${ASSET_ID:-0}, ${EXPENSE_ID:-0});
    delete from member_channel where external_id = '${TELEGRAM_ID}';
    delete from member_channel where external_id = '${UNLINKED_ID}';
    delete from member where id in (${ADMIN_ID}, ${MEMBER_A}, ${MEMBER_B});
  " >/dev/null 2>&1 || true
}
trap cleanup EXIT

bash scripts/link-telegram-channel.sh "$ADMIN_ID" "$MEMBER_A" "$TELEGRAM_ID" >/dev/null

ASSET_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into account (type, name) values ('asset', 'Assets:LinkingTestBank') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
EXPENSE_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into account (type, name) values ('expense', 'groceries') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
if [ -z "$EXPENSE_ID" ]; then
  EXPENSE_ID="$(psql_meowhub -t -A -c "select id from account where name = 'groceries' and type = 'expense' limit 1;")"
fi

CAPTURE_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', '${MEMBER_A}', true);
insert into transaction (date, submitter, source) values (current_date, ${MEMBER_A}, 'text') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
psql_meowhub -c "
  select set_config('meowhub.actor', '${MEMBER_A}', true);
  insert into posting (transaction_id, account_id, amount, currency) values (${CAPTURE_ID}, ${ASSET_ID}, -1000, 'EUR');
  insert into posting (transaction_id, account_id, amount, currency) values (${CAPTURE_ID}, ${EXPENSE_ID}, 1000, 'EUR');
" >/dev/null

# re-link the same Telegram id to a different member
psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  delete from member_channel where external_id = '${TELEGRAM_ID}';
" >/dev/null
bash scripts/link-telegram-channel.sh "$ADMIN_ID" "$MEMBER_B" "$TELEGRAM_ID" >/dev/null

original_submitter="$(psql_meowhub -t -A -c "select submitter from transaction where id = ${CAPTURE_ID};")"
current_link="$(psql_meowhub -t -A -c "select member_id from member_channel where external_id = '${TELEGRAM_ID}';")"

if [ "$original_submitter" = "$MEMBER_A" ] && [ "$current_link" = "$MEMBER_B" ]; then
  echo "PASS: a capture attributes to the member who made it, and a later re-link to a different account leaves it unchanged (A19)"
else
  echo "FAILED: expected the original capture to stay attributed to ${MEMBER_A} after re-linking to ${MEMBER_B}, got submitter=${original_submitter} current_link=${current_link}"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
