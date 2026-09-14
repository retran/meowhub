#!/usr/bin/env bash
# Proves spec 0004 T11: the weekly and monthly digests (A7, A8, A9, A10,
# A16). The clock is moved in SQL rather than waited for -- the tick
# takes the moment it is asked about, and the household's own timezone
# decides what "Monday 09:00" means.
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

TZ_NAME="$(psql_meowhub -t -A -c "select value #>> '{}' from household_setting where key = 'timezone';")"
MONDAY="$(psql_meowhub -t -A -c "select date_trunc('week', now() at time zone '${TZ_NAME}')::date;")"
FIRST="$(psql_meowhub -t -A -c "select date_trunc('month', now() at time zone '${TZ_NAME}')::date;")"

EN_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'en') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
RU_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language) values ('member', 'ru') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
OFF_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role, language, digest_weekly, digest_monthly) values ('member', 'en', false, false) returning id;
" | grep -E '^[0-9]+$' | tail -1)"

cleanup() {
  psql_meowhub -f /dev/stdin >/dev/null 2>&1 <<SQL || true
select set_config('meowhub.actor', 'test-suite', false);
delete from digest_run where member_id in (${EN_ID}, ${RU_ID}, ${OFF_ID});
delete from member where id in (${EN_ID}, ${RU_ID}, ${OFF_ID});
SQL
}
trap cleanup EXIT

tick() {
  $COMPOSE exec -T n8n wget -q -O- --post-data="{\"at\": \"$1\"}" \
    --header='Content-Type: application/json' http://localhost:5678/webhook/digest-tick 2>/dev/null || true
}

# What the tick said for one member and kind -- the digest's own text,
# so nothing here depends on Telegram having been reachable.
digest_text() {
  python3 -c "
import json, sys
payload = json.loads(sys.stdin.read() or '{}')
for row in (payload.get('sent') or []):
    if row.get('member_id') == int(sys.argv[1]) and row.get('kind') == sys.argv[2]:
        print(row.get('text') or '')
        break
" "$1" "$2"
}

money() { python3 -c "import sys; print(f'{int(sys.argv[1])/100:.2f}')" "$1"; }

# --- A10 / A16: the 1st, and a period with nothing in it --------------
# The monthly digest is tested first because it is overdue at every
# moment later in this test: once the 1st at 09:00 has passed, a member
# who has not had September's monthly digest is due it at any hour, and
# the first tick of any kind would send it.
first="$(tick "${FIRST} 09:00:00 ${TZ_NAME}")"
monthly_text="$(echo "$first" | digest_text "$EN_ID" monthly)"
MONTH_TOTAL="$(psql_meowhub -t -A -c "select amount_minor from v_period_spend where period = 'last_month';")"
if [ -n "$monthly_text" ]; then
  echo "PASS: the 1st sends the monthly digest (A16, R10, R17)"
else
  echo "FAILED: no monthly digest was sent on the 1st"
  fail=1
fi
if [ "$MONTH_TOTAL" = "0" ]; then
  lines="$(printf '%s\n' "$monthly_text" | grep -c '')"
  if [ "$lines" -eq 1 ] && echo "$monthly_text" | grep -qi "nothing"; then
    echo "PASS: a period with nothing in it is sent, and says so in one line (A10, R16)"
  else
    echo "FAILED: expected a one-line 'nothing' digest for an empty period, got '${monthly_text}'"
    fail=1
  fi
else
  if echo "$monthly_text" | grep -qF "$(money "$MONTH_TOTAL")"; then
    echo "PASS: the monthly digest carries last month's own figure (A8)"
  else
    echo "FAILED: expected $(money "$MONTH_TOTAL") in '${monthly_text}'"
    fail=1
  fi
fi

# --- A16: 08:59 is not yet due --------------------------------------
early="$(tick "${MONDAY} 08:59:00 ${TZ_NAME}")"
if [ -z "$(echo "$early" | digest_text "$EN_ID" weekly)" ]; then
  echo "PASS: a minute before Monday 09:00 nothing is due (A16)"
else
  echo "FAILED: a digest was sent at 08:59"
  fail=1
fi

# --- A7 / A8 / A17: Monday 09:00, one per member, in their language --
monday="$(tick "${MONDAY} 09:00:00 ${TZ_NAME}")"
en_text="$(echo "$monday" | digest_text "$EN_ID" weekly)"
ru_text="$(echo "$monday" | digest_text "$RU_ID" weekly)"

if [ -n "$en_text" ] && [ -n "$ru_text" ]; then
  echo "PASS: Monday 09:00 household time sends each member with digests enabled one weekly digest (A7, A16, R17)"
else
  echo "FAILED: expected a weekly digest for both members, got en='${en_text}' ru='${ru_text}'"
  fail=1
fi

if python3 -c "
import sys
print('yes' if any('Ѐ' <= ch <= 'ӿ' for ch in sys.argv[1]) else 'no')
" "$ru_text" | grep -q yes && ! python3 -c "
import sys
print('yes' if any('Ѐ' <= ch <= 'ӿ' for ch in sys.argv[1]) else 'no')
" "$en_text" | grep -q yes; then
  echo "PASS: each digest is in that member's own language (A7, R9)"
else
  echo "FAILED: languages did not follow the members: en='${en_text}' ru='${ru_text}'"
  fail=1
fi

WEEK_TOTAL="$(psql_meowhub -t -A -c "select amount_minor from v_period_spend where period = 'last_7_days';")"
WEEK_PREV="$(psql_meowhub -t -A -c "select previous_amount_minor from v_period_spend where period = 'last_7_days';")"
WEEK_UNCONF="$(psql_meowhub -t -A -c "select unconfirmed_amount_minor from v_period_spend where period = 'last_7_days';")"
if echo "$en_text" | grep -qF "$(money "$WEEK_TOTAL")" \
   && echo "$en_text" | grep -qF "$(money "$WEEK_PREV")" \
   && echo "$en_text" | grep -qF "$(money "$WEEK_UNCONF")"; then
  echo "PASS: the digest's figures are the ones the same questions return, from v_period_spend (A8, A17, R11, R13, R18)"
else
  echo "FAILED: expected total $(money "$WEEK_TOTAL"), previous $(money "$WEEK_PREV") and unconfirmed $(money "$WEEK_UNCONF") in '${en_text}'"
  fail=1
fi

if echo "$en_text" | grep -qiE "bank"; then
  echo "PASS: the digest states the period's reconciliation status rather than waiting for it (A16, R17)"
else
  echo "FAILED: the digest does not state its reconciliation status: '${en_text}'"
  fail=1
fi

# --- A9: digests turned off ------------------------------------------
if [ -z "$(echo "$monday" | digest_text "$OFF_ID" weekly)" ]; then
  runs="$(psql_meowhub -t -A -c "select count(*) from digest_run where member_id = ${OFF_ID};")"
  if [ "$runs" = "0" ]; then
    echo "PASS: a member who turned digests off receives nothing, and nothing is recorded as sent (A9, R15)"
  else
    echo "FAILED: a digest run was recorded for a member who turned digests off"
    fail=1
  fi
else
  echo "FAILED: a member who turned digests off received a digest"
  fail=1
fi

# --- A16: 09:01 does not send it a second time ------------------------
late="$(tick "${MONDAY} 09:01:00 ${TZ_NAME}")"
if [ -z "$(echo "$late" | digest_text "$EN_ID" weekly)" ]; then
  weekly_runs="$(psql_meowhub -t -A -c "select count(*) from digest_run where member_id = ${EN_ID} and kind = 'weekly' and period_start = '${MONDAY}';")"
  if [ "$weekly_runs" = "1" ]; then
    echo "PASS: a second tick in the same hour sends exactly one weekly digest (A16)"
  else
    echo "FAILED: expected exactly one weekly digest_run row, got ${weekly_runs}"
    fail=1
  fi
else
  echo "FAILED: the digest was sent twice"
  fail=1
fi


# --- R15: the member turns their own digests off, in the chat ---------
# A9 above proves the scheduler honours the preference; this proves the
# member can actually set it, which is what R15 asks for.
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

payload="$(python3 -c "
import json, sys
print(json.dumps({
  'member_id': int(sys.argv[1]), 'chat_id': int(sys.argv[1]) + 840000000, 'message_thread_id': None,
  'text': 'please stop sending me the weekly digest', 'language_hint': 'en', 'channel_message_id': None
}))
" "$EN_ID")"
# n8n reports healthy a moment before it has registered its webhooks
# again, so the first call after a restart can 404 -- and a lost call
# here would read as the member's preference not having changed.
for attempt in $(seq 1 10); do
  reply="$(bash scripts/proxy-curl.sh /webhook/agent-loop-test -X POST -H 'Content-Type: application/json' -d "$payload" 2>/dev/null || true)"
  case "$reply" in *'"text"'*) break ;; esac
  sleep 2
done

still_on="$(psql_meowhub -t -A -c "select digest_weekly from member where id = ${EN_ID};")"
if [ "$still_on" = "f" ]; then
  echo "PASS: a member can turn their own weekly digest off from the chat (R15)"
else
  echo "FAILED: asking Meow to stop sending the weekly digest left digest_weekly = '${still_on}'"
  fail=1
fi

$COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d n8n -c \
  "delete from workflow_entity where id='agenttestentry1'; delete from webhook_entity where \"workflowId\"='agenttestentry1';" >/dev/null

if [ "$fail" != "0" ]; then
  exit 1
fi
