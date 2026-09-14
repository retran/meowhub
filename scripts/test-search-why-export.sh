#!/usr/bin/env bash
# Proves spec 0004 T10: search, "why this category" and export are
# ordinary tools the agent calls (R19, R20, R21 -- A18, A19, A20).
#
# Nothing here asserts a figure written into this file: the export's
# total is compared with v_period_spend for the same period, so the CSV
# and the answers cannot drift apart without the test noticing.
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
CHAT_ID=$(( RANDOM + 830000000 ))
MARKER="zebracrossing$(printf %s "$$" | tr 0-9 a-j)"

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"

PAYMENT_ACCT="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='asset' and active limit 1;" | grep -E '^[0-9]+$' | tail -1)"
GROCERIES="$(psql_meowhub -t -A -c "select set_config('meowhub.actor','test-suite',false); select id from account where type='expense' and name='groceries' limit 1;" | grep -E '^[0-9]+$' | tail -1)"

# Two transactions with different provenance, and a note carrying a
# comma and a quote so the CSV has something real to escape (A20).
MODEL_TXN="$(psql_meowhub -t -A -f /dev/stdin <<SQL | grep -E '^[0-9]+$' | tail -1
select set_config('meowhub.actor', 'test-suite', false);
set role hh_agent;
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, note, category_source, model, prompt_version)
  values (current_date, ${MEMBER_ID}, 'text', 'confirmed', 'review',
          'lunch, the "good" place ${MARKER}', 'model', 'test/model-x', 'capture/v9')
  returning id;
SQL
)"
psql_meowhub -f /dev/stdin >/dev/null <<SQL
select set_config('meowhub.actor', 'test-suite', false);
set role hh_agent;
insert into posting (transaction_id, account_id, amount, currency)
  values (${MODEL_TXN}, ${PAYMENT_ACCT}, -1234, 'EUR'), (${MODEL_TXN}, ${GROCERIES}, 1234, 'EUR');
SQL

MERCHANT_ID="$(psql_meowhub -t -A -f /dev/stdin <<SQL | grep -E '^[0-9]+$' | tail -1
select set_config('meowhub.actor', 'test-suite', false);
set role hh_agent;
insert into merchant (name, default_category_id) values ('TestMart ${MARKER}', ${GROCERIES}) returning id;
SQL
)"
DEFAULT_TXN="$(psql_meowhub -t -A -f /dev/stdin <<SQL | grep -E '^[0-9]+$' | tail -1
select set_config('meowhub.actor', 'test-suite', false);
set role hh_agent;
insert into transaction (date, submitter, source, confirmation_state, confirmation_route, merchant_id, category_source)
  values (current_date, ${MEMBER_ID}, 'text', 'confirmed', 'review', ${MERCHANT_ID}, 'merchant_default')
  returning id;
SQL
)"
psql_meowhub -f /dev/stdin >/dev/null <<SQL
select set_config('meowhub.actor', 'test-suite', false);
set role hh_agent;
insert into posting (transaction_id, account_id, amount, currency)
  values (${DEFAULT_TXN}, ${PAYMENT_ACCT}, -777, 'EUR'), (${DEFAULT_TXN}, ${GROCERIES}, 777, 'EUR');
SQL

cleanup() {
  psql_meowhub -f /dev/stdin >/dev/null 2>&1 <<SQL || true
select set_config('meowhub.actor', 'test-suite', false);
delete from capture where member_id = ${MEMBER_ID};
delete from posting where transaction_id in (select id from transaction where submitter = ${MEMBER_ID});
delete from transaction where submitter = ${MEMBER_ID};
delete from merchant where id = ${MERCHANT_ID};
delete from member where id = ${MEMBER_ID};
SQL
}
trap cleanup EXIT

ask() {
  local payload
  payload="$(python3 -c "
import json, sys
print(json.dumps({
  'member_id': int(sys.argv[1]), 'chat_id': int(sys.argv[2]), 'message_thread_id': None,
  'text': sys.argv[3], 'language_hint': 'en', 'channel_message_id': None
}))
" "$MEMBER_ID" "$CHAT_ID" "$1")"
  bash scripts/proxy-curl.sh /webhook/agent-loop-test -X POST -H 'Content-Type: application/json' -d "$payload" 2>/dev/null || true
}

reply_text() { python3 -c "
import json, sys
try:
    print((json.loads(sys.stdin.read()) or {}).get('text') or '')
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

# --- A18: a word in a note finds the transaction ---------------------
search_reply="$(ask "search for ${MARKER}" | reply_text)"
if echo "$search_reply" | grep -qF "$(money 1234)" && echo "$search_reply" | grep -qF "$(money 777)"; then
  echo "PASS: searching a word from a note returns the transactions carrying it, with their amounts (A18, R19)"
else
  echo "FAILED: expected $(money 1234) and $(money 777) in the search reply, got '${search_reply}'"
  fail=1
fi

# --- A19: why this category, both provenances ------------------------
why_model="$(ask "why is #${MODEL_TXN} in that category" | reply_text)"
if echo "$why_model" | grep -qF 'test/model-x' && echo "$why_model" | grep -qF 'capture/v9'; then
  echo "PASS: a model-categorised transaction is explained by naming the model and the prompt version (A19, R20)"
else
  echo "FAILED: expected the model and prompt version in '${why_model}'"
  fail=1
fi

why_default="$(ask "why is #${DEFAULT_TXN} in that category" | reply_text)"
if echo "$why_default" | grep -qiF 'merchant default' && ! echo "$why_default" | grep -qF 'test/model-x'; then
  echo "PASS: a merchant-default categorisation says so instead, and names no model (A19, R20)"
else
  echo "FAILED: expected a merchant default and no model in '${why_default}'"
  fail=1
fi

# --- A20: the export agrees with the views and parses as RFC 4180 ----
export_raw="$(ask 'export this month as csv')"
python3 - "$export_raw" > /tmp/meowhub-export.csv <<'PY'
import csv, io, json, sys
payload = json.loads(sys.argv[1] or "{}")
csvs = [t["result"]["csv"] for t in (payload.get("tool_results") or [])
        if t.get("tool") == "export_period" and (t.get("result") or {}).get("csv")]
if not csvs:
    sys.exit("no export_period result carrying a CSV")
sys.stdout.write(csvs[0])
PY
if [ -s /tmp/meowhub-export.csv ]; then
  echo "PASS: the export tool returned a CSV (A20, R21)"
else
  echo "FAILED: the agent produced no CSV for an export request"
  fail=1
fi

VIEW_TOTAL="$(psql_meowhub -t -A -c "select amount_minor from v_period_spend where period = 'this_month';")"
CSV_TOTAL="$(python3 - <<'PY'
import csv
with open('/tmp/meowhub-export.csv', newline='') as fh:
    rows = list(csv.DictReader(fh))
print(sum(int(r['amount_minor']) for r in rows if r['account_type'] == 'expense'))
PY
)"
if [ "$CSV_TOTAL" = "$VIEW_TOTAL" ]; then
  echo "PASS: the CSV's expense total equals v_period_spend for the same period (A20, R13)"
else
  echo "FAILED: the CSV totals ${CSV_TOTAL} but v_period_spend says ${VIEW_TOTAL}"
  fail=1
fi

# A file a spreadsheet opens without repair: CRLF records, doubled
# quotes, and the awkward note surviving the round trip intact.
if python3 - "$MARKER" <<'PY'
import csv, sys
marker = sys.argv[1]
raw = open('/tmp/meowhub-export.csv', newline='').read()
assert raw.endswith('\r\n'), 'records must end CRLF'
rows = list(csv.DictReader(open('/tmp/meowhub-export.csv', newline='')))
notes = [r['note'] for r in rows if marker in (r['note'] or '')]
assert notes, 'the awkward note is missing from the export'
assert notes[0] == f'lunch, the "good" place {marker}', f'note came back as {notes[0]!r}'
PY
then
  echo "PASS: the CSV is RFC 4180 -- CRLF records, and a note with a comma and a quote survives the round trip (A20)"
else
  echo "FAILED: the CSV does not parse as RFC 4180"
  fail=1
fi
rm -f /tmp/meowhub-export.csv

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='agenttestentry1'; delete from webhook_entity where \"workflowId\"='agenttestentry1';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
