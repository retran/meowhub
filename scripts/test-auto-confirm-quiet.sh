#!/usr/bin/env bash
# Proves spec 0003 T12/A25: a capture at a merchant never seen before
# stays unconfirmed; a capture at a known merchant, its own category,
# below the household's threshold, becomes confirmed with the quiet
# route recorded once its quiet period has actually elapsed -- driven
# through the real capture-text flow and the real scheduled job, not
# asserted directly against the database.
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
TELEGRAM_ID=$(( RANDOM + 800000000 ))

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language, default_payment_account_id) values ('admin', 'en', (select id from account where type='asset' and active limit 1)) returning id;
" | grep -E '^[0-9]+$' | tail -1)"

psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', true);
  insert into member_channel (member_id, kind, external_id, linked_by) values (${MEMBER_ID}, 'telegram', '${TELEGRAM_ID}', ${MEMBER_ID});
" >/dev/null

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    update member set default_payment_account_id = null where id = ${MEMBER_ID};
    delete from capture where member_id = ${MEMBER_ID};
    delete from posting where transaction_id in (select id from transaction where submitter = ${MEMBER_ID});
    delete from transaction where submitter = ${MEMBER_ID};
    delete from member_channel where member_id = ${MEMBER_ID};
    delete from member where id = ${MEMBER_ID};
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
  'source': 'auto-confirm-test'
}))
" "$update_id" "$telegram_id" "$text")"
  bash scripts/proxy-curl.sh /webhook/auto-confirm-test -X POST -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
}

TMP="$(mktemp)"
cat > "$TMP" <<'JSON'
{
  "id": "acqtestentry0001",
  "name": "auto-confirm-test-entry",
  "nodes": [
    {"parameters": {"httpMethod": "POST", "path": "auto-confirm-test", "responseMode": "responseNode", "options": {}},
     "id": "v0000000-0000-4000-8000-000000000001", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0], "webhookId": "auto-confirm-test"},
    {"parameters": {"jsCode": "return [{ json: $json.body }];"},
     "id": "v0000000-0000-4000-8000-000000000004", "name": "Unwrap",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [140, 0]},
    {"parameters": {"source": "database", "workflowId": {"__rl": true, "value": "tgdispatch00001", "mode": "id"}, "options": {}},
     "id": "v0000000-0000-4000-8000-000000000002", "name": "Dispatch",
     "type": "n8n-nodes-base.executeWorkflow", "typeVersion": 1.3, "position": [280, 0]},
    {"parameters": {"respondWith": "json", "responseBody": "={{ { done: true } }}", "options": {}},
     "id": "v0000000-0000-4000-8000-000000000003", "name": "Respond",
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
docker compose cp "$TMP" n8n:/tmp/auto-confirm-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/auto-confirm-test-entry.json >/dev/null
$COMPOSE exec -T n8n n8n publish:workflow --id=acqtestentry0001 >/dev/null
$COMPOSE restart n8n >/dev/null
bash scripts/wait-for-n8n.sh
rm -f "$TMP"

# Half of A25: a merchant never seen before stays unconfirmed.
send_message "widgets 500 at some brand new shop" "$TELEGRAM_ID" $(( RANDOM + 100000000 ))
sleep 1
UNKNOWN_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', false);
  update transaction set created_at = now() - interval '48 hours' where id = ${UNKNOWN_TXN};
" >/dev/null

# The other half: a known merchant, its own category, below the
# threshold (2000 minor = 20.00 EUR, seeded), backdated past the
# 24-hour quiet period (also seeded).
send_message "groceries 15,00 albert heijn" "$TELEGRAM_ID" $(( RANDOM + 150000000 ))
sleep 1
KNOWN_TXN="$(psql_meowhub -t -A -c "select id from transaction where submitter = ${MEMBER_ID} order by id desc limit 1;")"
known_state_before="$(psql_meowhub -t -A -c "select confirmation_state, category_source from transaction where id = ${KNOWN_TXN};")"
if echo "$known_state_before" | grep -q "unconfirmed|merchant_default"; then
  echo "PASS: a known-merchant capture below the threshold starts unconfirmed with category_source recorded"
else
  echo "FAILED: expected 'unconfirmed|merchant_default' before the quiet period, got '${known_state_before}'"
  fail=1
fi
psql_meowhub -c "
  select set_config('meowhub.actor', 'test-suite', false);
  update transaction set created_at = now() - interval '48 hours' where id = ${KNOWN_TXN};
" >/dev/null

bash scripts/auto-confirm-quiet.sh >/dev/null

unknown_after="$(psql_meowhub -t -A -c "select confirmation_state from transaction where id = ${UNKNOWN_TXN};")"
if [ "$unknown_after" = "unconfirmed" ]; then
  echo "PASS: a never-seen merchant's capture is not auto-confirmed, however old (A25)"
else
  echo "FAILED: expected the unknown-merchant capture to remain unconfirmed, got '${unknown_after}'"
  fail=1
fi

known_after="$(psql_meowhub -t -A -c "select confirmation_state || '|' || confirmation_route from transaction where id = ${KNOWN_TXN};")"
if [ "$known_after" = "confirmed|quiet" ]; then
  echo "PASS: a known merchant's own category below the threshold auto-confirms with the quiet route recorded, once the quiet period elapses (A25)"
else
  echo "FAILED: expected 'confirmed|quiet' after the quiet period, got '${known_after}'"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='acqtestentry0001'; delete from webhook_entity where \"workflowId\"='acqtestentry0001';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
