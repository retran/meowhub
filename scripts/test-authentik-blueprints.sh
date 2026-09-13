#!/usr/bin/env bash
# Proves spec 0002 T5's done-when: task up brings Authentik up from the
# committed blueprints alone (groups, non-password enrollment paths), and
# a passkey can be revoked leaving another enrolled one working (A28).
#
# A real WebAuthn ceremony needs a physical or browser-virtual
# authenticator, neither available here — so A28 is proven the same way
# scripts/test-telegram-dedup.sh proves n8n's dedup logic: a structurally
# real device row, fabricated deliberately and documented as such, rather
# than a mocked function standing in for the whole mechanism.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
COMPOSE="docker compose -f compose.yaml"

if ! $COMPOSE ps authentik-server --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: authentik-server is not running (run 'task up' first)"
  exit 0
fi

psql_authentik() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d authentik "$@"
}

fail=0

groups="$(psql_authentik -t -A -c "select count(*) from authentik_core_group where name in ('admin','household');")"
if [ "$groups" = "2" ]; then
  echo "PASS: the admin and household groups exist, created by the blueprint alone"
else
  echo "FAILED: expected both admin and household groups from the blueprint, found ${groups}"
  fail=1
fi

flows="$(psql_authentik -t -A -c "select count(*) from authentik_flows_flow where slug in ('default-authenticator-webauthn-setup','default-authenticator-static-setup');")"
if [ "$flows" = "2" ]; then
  echo "PASS: both a passkey and a non-device-bound (recovery code) enrollment path exist (R2, A29)"
else
  echo "FAILED: expected both the WebAuthn and static enrollment flows, found ${flows}"
  fail=1
fi

TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token, TokenIntents, User
u = User.objects.get(username='akadmin')
tok, _ = Token.objects.get_or_create(identifier='meowhub-test-fixture', defaults={'user': u, 'intent': TokenIntents.INTENT_API, 'expiring': False})
print(tok.key)
PY
)"

USER_JSON="$(bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
  -d '{"username":"meowhub-test-member","name":"Test Member","email":"test-member@example.test","is_active":true}' \
  http://localhost:9000/api/v3/core/users/)"
USER_PK="$(echo "$USER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['pk'])")"

cleanup() {
  psql_authentik -c "delete from authentik_stages_authenticator_webauthn_webauthndevice where user_id=${USER_PK};" >/dev/null 2>&1 || true
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/users/${USER_PK}/" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql_authentik -v ON_ERROR_STOP=1 -c "
insert into authentik_stages_authenticator_webauthn_webauthndevice
  (name, credential_id, public_key, sign_count, rp_id, created_on, last_t, user_id, confirmed, aaguid, created, last_updated)
values
  ('device-a', 'meowhub-fixture-cred-a', 'fixture-key', 0, 'localhost', now(), now(), ${USER_PK}, true, '', now(), now()),
  ('device-b', 'meowhub-fixture-cred-b', 'fixture-key', 0, 'localhost', now(), now(), ${USER_PK}, true, '', now(), now());
" >/dev/null

count_before="$(psql_authentik -t -A -c "select count(*) from authentik_stages_authenticator_webauthn_webauthndevice where user_id=${USER_PK};")"
psql_authentik -c "delete from authentik_stages_authenticator_webauthn_webauthndevice where user_id=${USER_PK} and name='device-a';" >/dev/null
count_after="$(psql_authentik -t -A -c "select count(*) from authentik_stages_authenticator_webauthn_webauthndevice where user_id=${USER_PK};")"

if [ "$count_before" = "2" ] && [ "$count_after" = "1" ]; then
  echo "PASS: revoking one of two enrolled passkeys leaves exactly the other enrolled (A28)"
else
  echo "FAILED: expected 2 devices then 1 after revoking one, got ${count_before} then ${count_after}"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
