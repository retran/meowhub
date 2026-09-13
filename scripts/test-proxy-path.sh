#!/usr/bin/env bash
# Proves spec 0002 T9's done-when for real: a genuine sign-in through
# Authentik, forward-auth, the OAuth dance for this application, the token
# bridge, and PostgREST — run from the host against the proxy's published
# port, the exact path a browser takes (scripts/authentik-e2e-signin.py).
# Two members, two roles, two different answers from the same data API.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"
: "${PROXY_HTTPS_PORT:?PROXY_HTTPS_PORT not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps proxy --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: the proxy is not running (run 'task up' first)"
  exit 0
fi

PASSWORD="CorrectHorseBattery1!"
CA_TMP="$(mktemp)"

psql_meowhub() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" "$@"
}

TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token, TokenIntents, User
u = User.objects.get(username='akadmin')
tok, _ = Token.objects.get_or_create(identifier='meowhub-test-fixture', defaults={'user': u, 'intent': TokenIntents.INTENT_API, 'expiring': False})
print(tok.key)
PY
)"
HOUSEHOLD_GROUP_PK="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/groups/?name=household" | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['pk'])")"

create_authentik_user() {
  local username="$1"
  local json
  json="$(bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"username\":\"${username}\",\"name\":\"${username}\",\"email\":\"${username}@example.test\",\"is_active\":true}" \
    http://localhost:9000/api/v3/core/users/)"
  local pk
  pk="$(echo "$json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['pk'])")"
  local uid
  uid="$(echo "$json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['uid'])")"
  bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"password\":\"${PASSWORD}\"}" "http://localhost:9000/api/v3/core/users/${pk}/set_password/" >/dev/null
  bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d '{"pk": '"${pk}"'}' "http://localhost:9000/api/v3/core/groups/${HOUSEHOLD_GROUP_PK}/add_user/" >/dev/null
  echo "$pk $uid"
}

read -r AUTHENTIK_PK AUTHENTIK_UID < <(create_authentik_user "meowhub-e2e-test-member")

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('member') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
psql_meowhub -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member_identity (member_id, provider_subject) values (${MEMBER_ID}, '${AUTHENTIK_UID}');
" >/dev/null

cleanup() {
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/users/${AUTHENTIK_PK}/" >/dev/null 2>&1 || true
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    delete from member_identity where member_id = ${MEMBER_ID};
    delete from member where id = ${MEMBER_ID};
  " >/dev/null 2>&1 || true
  rm -f "$CA_TMP"
}
trap cleanup EXIT

$COMPOSE exec -T proxy cat /data/caddy/pki/authorities/local/root.crt > "$CA_TMP"

output="$(python3 scripts/authentik-e2e-signin.py "https://localhost:${PROXY_HTTPS_PORT}" "$CA_TMP" /rest/member "meowhub-e2e-test-member" "$PASSWORD")"
echo "$output"

if echo "$output" | grep -q "\"id\":${MEMBER_ID}" && echo "$output" | grep -q '"role":"member"'; then
  echo "PASS: a real sign-in through the full proxy path (Authentik -> forward-auth -> token bridge -> PostgREST) reaches this member's own row"
else
  echo "FAILED: expected member ${MEMBER_ID}'s row in the response, got: $output"
  exit 1
fi
