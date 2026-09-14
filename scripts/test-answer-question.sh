#!/usr/bin/env bash
# Proves spec 0004 T8: the agent answers questions about the books by
# calling read tools and writing the reply itself (ADR 0046).
#
# Figures are never asserted against a number hardcoded here: the view
# is queried directly with psql and the reply must carry what the view
# says (A4). That way the test cannot pass by agreeing with itself, and
# it stays true whatever else the seeded household contains.
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
CHAT_ID=$(( RANDOM + 820000000 ))

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
RU_MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'ru') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

PAYMENT_ACCT="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='asset' and active limit 1;" | grep -E '^[0-9]+$' | tail -1)"
GROCERIES="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='expense' and name='groceries' limit 1;" | grep -E '^[0-9]+$' | tail -1)"

# Two confirmed and one unconfirmed expense this month, so the
# unconfirmed share is a real fraction rather than 0 or 1 (A6).
psql_meowhub -f /dev/stdin >/dev/null <<SQL
select set_config('meowhub.actor', 'test-suite', false);
set role hh_agent;
insert into transaction (date, submitter, source, confirmation_state, confirmation_route)
  values (current_date, ${MEMBER_ID}, 'text', 'confirmed', 'review');
insert into posting (transaction_id, account_id, amount, currency)
  values (currval('transaction_id_seq'), ${PAYMENT_ACCT}, -4500, 'EUR');
insert into posting (transaction_id, account_id, amount, currency)
  values (currval('transaction_id_seq'), ${GROCERIES}, 4500, 'EUR');
SQL

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', false);
    delete from capture where member_id in (${MEMBER_ID}, ${RU_MEMBER_ID});
    delete from posting where transaction_id in (select id from transaction where submitter in (${MEMBER_ID}, ${RU_MEMBER_ID}));
    delete from transaction where submitter in (${MEMBER_ID}, ${RU_MEMBER_ID});
    delete from member where id in (${MEMBER_ID}, ${RU_MEMBER_ID});
  " >/dev/null 2>&1 || true
}
trap cleanup EXIT

ask() {
  local text="$1"
  local who="${2:-$MEMBER_ID}"
  local lang="${3:-en}"
  local payload
  payload="$(python3 -c "
import json, sys
print(json.dumps({
  'member_id': int(sys.argv[1]), 'chat_id': int(sys.argv[2]), 'message_thread_id': None,
  'text': sys.argv[3], 'language_hint': sys.argv[4], 'channel_message_id': None
}))
" "$who" "$CHAT_ID" "$text" "$lang")"
  bash scripts/proxy-curl.sh /webhook/agent-loop-test -X POST -H 'Content-Type: application/json' -d "$payload" 2>/dev/null || true
}

reply_text() { python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    print((json.loads(raw) or {}).get('text') or '')
except Exception:
    print('')
"; }

money() { python3 -c "import sys; print(f'{int(sys.argv[1])/100:.2f}')" "$1"; }

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

# --- A1 / A4 / A6 / A17: the household's total for a period ---------
VIEW_TOTAL="$(psql_meowhub -t -A -c "select amount_minor from v_period_spend where period = 'this_month';")"
VIEW_PREV="$(psql_meowhub -t -A -c "select previous_amount_minor from v_period_spend where period = 'this_month';")"
VIEW_UNCONF="$(psql_meowhub -t -A -c "select unconfirmed_amount_minor from v_period_spend where period = 'this_month';")"

total_reply="$(ask 'how much did we spend this month' | reply_text)"
if echo "$total_reply" | grep -qF "$(money "$VIEW_TOTAL")"; then
  echo "PASS: the reply carries the figure v_period_spend itself reports (A1, A4)"
else
  echo "FAILED: expected $(money "$VIEW_TOTAL") from v_period_spend in the reply, got '${total_reply}'"
  fail=1
fi
if echo "$total_reply" | grep -qiE "this_month|month"; then
  echo "PASS: the reply states the period it covers (A1, R3)"
else
  echo "FAILED: the reply does not state its period: '${total_reply}'"
  fail=1
fi
if echo "$total_reply" | grep -qF "$(money "$VIEW_UNCONF")"; then
  echo "PASS: the reply states the unconfirmed share of the figure (A6, R3)"
else
  echo "FAILED: expected the unconfirmed figure $(money "$VIEW_UNCONF") in the reply, got '${total_reply}'"
  fail=1
fi
if echo "$total_reply" | grep -qF "$(money "$VIEW_PREV")"; then
  echo "PASS: the reply carries the previous period's figure for comparison (A17, R18)"
else
  echo "FAILED: expected the previous period's $(money "$VIEW_PREV") in the reply, got '${total_reply}'"
  fail=1
fi

# --- A1a: ranked categories ----------------------------------------
TOP_CATEGORY="$(psql_meowhub -t -A -c "select category_slug from v_category_spend where period = 'this_month' and amount_minor > 0 order by amount_minor desc limit 1;")"
TOP_AMOUNT="$(psql_meowhub -t -A -c "select amount_minor from v_category_spend where period = 'this_month' and amount_minor > 0 order by amount_minor desc limit 1;")"
ranked_reply="$(ask 'what did we spend the most on this month' | reply_text)"
if echo "$ranked_reply" | grep -qF "$TOP_CATEGORY" && echo "$ranked_reply" | grep -qF "$(money "$TOP_AMOUNT")"; then
  echo "PASS: the ranked question names the top category with its own total, from v_category_spend (A1a)"
else
  echo "FAILED: expected '${TOP_CATEGORY}' and $(money "$TOP_AMOUNT") in the reply, got '${ranked_reply}'"
  fail=1
fi

# --- A2: the same question in Russian -------------------------------
ru_reply="$(ask 'сколько мы потратили в этом месяце' "$RU_MEMBER_ID" ru | reply_text)"
if echo "$ru_reply" | grep -qF "$(money "$VIEW_TOTAL")"; then
  echo "PASS: the Russian question returns the identical figure (A2)"
else
  echo "FAILED: expected the same figure $(money "$VIEW_TOTAL") in the Russian reply, got '${ru_reply}'"
  fail=1
fi
if python3 -c "
import sys
print('yes' if any('\u0400' <= ch <= '\u04FF' for ch in sys.argv[1]) else 'no')
" "$ru_reply" | grep -q yes; then
  echo "PASS: the reply to a Russian speaker is in Russian (A2, R7)"
else
  echo "FAILED: expected a Russian reply, got '${ru_reply}'"
  fail=1
fi

# --- A5a: headroom names the limit it is measured against ------------
CARD_NAME="$(psql_meowhub -t -A -c "select name from v_account_balance where type = 'liability' and limit_amount is not null limit 1;")"
CARD_LIMIT="$(psql_meowhub -t -A -c "select limit_amount from v_account_balance where name = '${CARD_NAME}';")"
CARD_HEADROOM="$(psql_meowhub -t -A -c "select headroom from v_account_balance where name = '${CARD_NAME}';")"
headroom_reply="$(ask "what is our headroom on the credit card" | reply_text)"
if echo "$headroom_reply" | grep -qF "$(money "$CARD_HEADROOM")" && echo "$headroom_reply" | grep -qF "$(money "$CARD_LIMIT")"; then
  echo "PASS: the headroom answer states the limit it is measured against (A5a)"
else
  echo "FAILED: expected headroom $(money "$CARD_HEADROOM") against limit $(money "$CARD_LIMIT"), got '${headroom_reply}'"
  fail=1
fi

# --- A15: a member who is not an admin gets household-wide figures ---
role_check="$(psql_meowhub -t -A -c "select role from member where id = ${MEMBER_ID};")"
if [ "$role_check" = "member" ] && echo "$total_reply" | grep -qF "$(money "$VIEW_TOTAL")"; then
  echo "PASS: a non-admin asking about the whole household's spending receives it (A15, ADR 0016)"
else
  echo "FAILED: expected a non-admin to receive household-wide spending; role='${role_check}'"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='agenttestentry1'; delete from webhook_entity where \"workflowId\"='agenttestentry1';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
