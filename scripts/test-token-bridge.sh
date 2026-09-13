#!/usr/bin/env bash
# Proves spec 0002 T7's done-when directly, against the real running
# bridge: a real Authentik account in the "admin" group, linked to a real
# member, gets back a token with the correct role and member_id claims
# (ADR 0041), and a subject with no member_identity row is refused
# outright (A22) — no token minted, not one PostgREST would later reject.
#
# The fixture is a real Authentik user (not a fabricated X-Authentik-Uid
# header) because the bridge resolves group membership from Authentik's
# own API now, not from a forward-auth header (spec 0002 T10 — that
# header turned out to omit a user's groups unpredictably).
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"
: "${PGRST_JWT_SECRET:?PGRST_JWT_SECRET not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps token-bridge --format '{{.State}}' 2>/dev/null | grep -q running; then
  echo "SKIPPED: token-bridge is not running (run 'task up' first)"
  exit 0
fi

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
ADMIN_GROUP_PK="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/groups/?name=admin" | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['pk'])")"

json="$(bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
  -d '{"username":"meowhub-bridge-test-admin","name":"meowhub-bridge-test-admin","email":"meowhub-bridge-test-admin@example.test","is_active":true}' \
  http://localhost:9000/api/v3/core/users/)"
AUTHENTIK_PK="$(echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin)['pk'])")"
AUTHENTIK_UID="$(echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin)['uid'])")"
bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
  -d '{"pk": '"${AUTHENTIK_PK}"'}' "http://localhost:9000/api/v3/core/groups/${ADMIN_GROUP_PK}/add_user/" >/dev/null

MEMBER_ID="$(psql_meowhub -t -A -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member (role) values ('admin') returning id;
" | grep -E '^[0-9]+$' | tail -1)"
psql_meowhub -c "
select set_config('meowhub.actor', 'test-suite', true);
insert into member_identity (member_id, provider_subject) values (${MEMBER_ID}, '${AUTHENTIK_UID}');
" >/dev/null

cleanup() {
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/users/${AUTHENTIK_PK}/" >/dev/null 2>&1 || true
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    delete from member_identity where provider_subject = '${AUTHENTIK_UID}';
    delete from member where id = ${MEMBER_ID};
  " >/dev/null 2>&1 || true
}
trap cleanup EXIT

CID="$($COMPOSE ps -q token-bridge)"
fail=0

response="$(docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 -sS -D - -o /dev/null \
  -H "X-Authentik-Uid: ${AUTHENTIK_UID}" http://localhost:8095/)"

if ! echo "$response" | grep -q "^HTTP/1.0 200"; then
  echo "FAILED: a known member with a recognised group should get 200, got: $response"
  fail=1
else
  token="$(echo "$response" | grep -i '^Authorization:' | sed 's/^[Aa]uthorization: Bearer //' | tr -d '\r')"
  claims="$(python3 -c "
import base64, json, sys
token = sys.argv[1]
header, payload, sig = token.split('.')
pad = lambda s: s + '=' * (-len(s) % 4)
print(json.loads(base64.urlsafe_b64decode(pad(payload))))
" "$token")"
  echo "claims: $claims"
  if echo "$claims" | grep -q "'role': 'hh_admin'" && echo "$claims" | grep -q "'member_id': ${MEMBER_ID}"; then
    echo "PASS: the bridge mints a token with the correct role and member_id claims"
  else
    echo "FAILED: expected role hh_admin and member_id ${MEMBER_ID}, got: $claims"
    fail=1
  fi
fi

response="$(docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 -sS -D - -o /dev/null \
  -H "X-Authentik-Uid: no-such-subject-at-all" http://localhost:8095/)"
if echo "$response" | grep -q "^HTTP/1.0 403"; then
  echo "PASS: a subject with no member_identity row is refused outright, nothing minted (A22)"
else
  echo "FAILED: expected 403 for an unresolvable subject, got: $response"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
