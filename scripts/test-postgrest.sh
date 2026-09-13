#!/usr/bin/env bash
# Proves spec 0002 T8's done-when against the real running PostgREST: a
# tampered-role token (A15) and an expired one (A16) are both rejected by
# PostgREST itself, not by the token bridge — the bridge never even sees
# these, since a real attacker would go straight at the data API with a
# forged token, not through the bridge's own minting path.
set -euo pipefail

: "${PGRST_JWT_SECRET:?PGRST_JWT_SECRET not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps postgrest --format '{{.State}}' 2>/dev/null | grep -q running; then
  echo "SKIPPED: postgrest is not running (run 'task up' first)"
  exit 0
fi

CID="$($COMPOSE ps -q postgrest)"
fail=0

TOKENS="$(python3 -c "
import base64, hashlib, hmac, json, time, sys

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

def make_jwt(payload, secret):
    header = b64url(json.dumps({'alg': 'HS256', 'typ': 'JWT'}).encode())
    body = b64url(json.dumps(payload).encode())
    sig = b64url(hmac.new(secret.encode(), f'{header}.{body}'.encode(), hashlib.sha256).digest())
    return f'{header}.{body}.{sig}'

real_secret = sys.argv[1]
wrong_secret = real_secret + '-but-wrong'

print('TAMPERED=' + make_jwt({'role': 'hh_admin', 'member_id': 1, 'exp': int(time.time()) + 300}, wrong_secret))
print('EXPIRED=' + make_jwt({'role': 'hh_admin', 'member_id': 1, 'exp': int(time.time()) - 300}, real_secret))
print('VALID=' + make_jwt({'role': 'hh_member', 'member_id': 1, 'exp': int(time.time()) + 300}, real_secret))
" "$PGRST_JWT_SECRET")"
eval "$TOKENS"

status_for() {
  local token="$1"
  docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" http://localhost:3000/member
}

code="$(status_for "$TAMPERED")"
if [ "$code" = "401" ]; then
  echo "PASS: a tampered-role token (re-signed with a different secret) is rejected by PostgREST (A15)"
else
  echo "FAILED: expected 401 for a tampered token, got ${code}"
  fail=1
fi

code="$(status_for "$EXPIRED")"
if [ "$code" = "401" ]; then
  echo "PASS: an expired token is rejected by PostgREST (A16)"
else
  echo "FAILED: expected 401 for an expired token, got ${code}"
  fail=1
fi

code="$(status_for "$VALID")"
if [ "$code" = "200" ]; then
  echo "PASS: a genuinely valid token is accepted by PostgREST"
else
  echo "FAILED: expected 200 for a valid token, got ${code}"
  fail=1
fi

code="$(docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 -sS -o /dev/null -w '%{http_code}' http://localhost:3000/member)"
if [ "$code" = "401" ]; then
  echo "PASS: no token at all reads nothing — anon holds no grant, not even the schema (A14)"
else
  echo "FAILED: expected 401 with no token, got ${code}"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
