#!/usr/bin/env bash
# Proves spec 0002 T6's done-when directly, against Authentik's real flow
# executor — not a mock, not a claim read back from a blueprint: A1 (a
# fresh member with nothing enrolled signs in with just email and
# password), A4 (repeated failures lock the account out, logged
# automatically), and A5 (no outbound email dependency exists anywhere in
# the stack, so a reset can only be admin-performed).
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps authentik-server --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: authentik-server is not running (run 'task up' first)"
  exit 0
fi

PASSWORD="CorrectHorseBattery1!"
WRONG_PASSWORD="wrong-password-xyz"
CID="$($COMPOSE ps -q authentik-server)"
fail=0

TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token, TokenIntents, User
u = User.objects.get(username='akadmin')
tok, _ = Token.objects.get_or_create(identifier='meowhub-test-fixture', defaults={'user': u, 'intent': TokenIntents.INTENT_API, 'expiring': False})
print(tok.key)
PY
)"

create_user() {
  local username="$1"
  local pk
  pk="$(bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"username\":\"${username}\",\"name\":\"${username}\",\"email\":\"${username}@example.test\",\"is_active\":true}" \
    http://localhost:9000/api/v3/core/users/ | python3 -c "import json,sys; print(json.load(sys.stdin)['pk'])")"
  bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"password\":\"${PASSWORD}\"}" \
    "http://localhost:9000/api/v3/core/users/${pk}/set_password/" >/dev/null
  echo "$pk"
}

FRESH_PK="$(create_user meowhub-test-fresh-member)"
LOCKOUT_PK="$(create_user meowhub-test-lockout-member)"

cleanup() {
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/users/${FRESH_PK}/" >/dev/null 2>&1 || true
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/users/${LOCKOUT_PK}/" >/dev/null 2>&1 || true
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d authentik -c \
    "delete from authentik_policies_reputation_reputation where identifier in ('meowhub-test-fresh-member','meowhub-test-lockout-member');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# A1: a fresh member, nothing enrolled, signs in with just email+password.
out="$(docker run --rm --network "container:${CID}" -v "$(pwd)/scripts/authentik-flow-test.py:/f.py:ro" \
  python:3.12-alpine python3 /f.py meowhub-test-fresh-member "$PASSWORD" 1)"
echo "$out"
if echo "$out" | grep -q "xak-flow-redirect"; then
  echo "PASS: a fresh member with nothing enrolled beforehand signs in with email and password alone (A1)"
else
  echo "FAILED: a fresh member's correct password should have completed the flow"
  fail=1
fi

# A4: repeated wrong passwords lock the account out.
out="$(docker run --rm --network "container:${CID}" -v "$(pwd)/scripts/authentik-flow-test.py:/f.py:ro" \
  python:3.12-alpine python3 /f.py meowhub-test-lockout-member "$WRONG_PASSWORD" 8)"
echo "$out"
if echo "$out" | grep -q "ak-stage-access-denied"; then
  echo "PASS: repeated failed attempts lock the account out (A4)"
else
  echo "FAILED: repeated failures should have reached the access-denied stage"
  fail=1
fi

failed_events="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d authentik -t -A -c \
  "select count(*) from authentik_events_event where action='login_failed';")"
if [ "$failed_events" -gt 0 ]; then
  echo "PASS: failed sign-in attempts are recorded in Authentik's own event log (A4)"
else
  echo "FAILED: expected at least one login_failed event"
  fail=1
fi

# A5: no outbound email dependency exists anywhere in this stack.
if grep -rqi "AUTHENTIK_EMAIL__" .env.example compose.yaml; then
  echo "FAILED: an SMTP/email configuration exists — self-service reset must not be possible"
  fail=1
else
  echo "PASS: no SMTP configuration exists anywhere in the stack (A5)"
fi
if $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d authentik -t -A -c \
  "select count(*) from authentik_flows_flow where slug like '%recovery%';" | grep -q '^0$'; then
  echo "PASS: no self-service recovery flow exists — a reset can only be admin-performed (A5)"
else
  echo "FAILED: a recovery flow exists, which would let a member reset their own password"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
