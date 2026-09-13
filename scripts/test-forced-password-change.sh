#!/usr/bin/env bash
# Proves spec 0002 T13's A1b for real: a temporary password an admin set
# reaches nothing until the member changes it, a repeated sign-in with
# that same temporary password behaves identically (not "invalid
# password" — still just re-prompted), and only after the change does a
# sign-in complete — with the temporary password now genuinely dead.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"

COMPOSE="docker compose -f compose.yaml"
if ! $COMPOSE ps authentik-server --format '{{.Health}}' 2>/dev/null | grep -q healthy; then
  echo "SKIPPED: authentik-server is not running (run 'task up' first)"
  exit 0
fi

psql_meowhub() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" "$@"
}

EXISTING="$(psql_meowhub -t -A -c "select count(*) from member;")"
if [ "$EXISTING" = "0" ]; then
  BOOTSTRAP_OUT="$(bash scripts/create-member.sh admin fpc-test-admin@example.test)"
  ADMIN_ID="$(echo "$BOOTSTRAP_OUT" | grep -o 'member [0-9]*' | grep -o '[0-9]*')"
else
  ADMIN_ID="$(psql_meowhub -t -A -c "select id from member where role = 'admin' limit 1;")"
fi

OUT="$(bash scripts/create-member.sh member fpc-test-member@example.test "$ADMIN_ID")"
EMAIL="fpc-test-member@example.test"
TEMP_PASSWORD="$(echo "$OUT" | sed -n 's/^temporary password: //p')"
MEMBER_ID="$(echo "$OUT" | grep -o 'member [0-9]*' | grep -o '[0-9]*' | head -1)"
USERNAME="${EMAIL%%@*}"

cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    delete from member_identity where member_id = ${MEMBER_ID};
    delete from member where id = ${MEMBER_ID};
  " >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail=0
NEW_PASSWORD="CorrectHorseBattery2!"
CID="$($COMPOSE ps -q authentik-server)"

DRIVER="$(mktemp)"
cat > "$DRIVER" <<'PY'
import http.cookiejar, json, sys, urllib.request

BASE = "http://localhost:9000"
FLOW = "default-authentication-flow"
username, temp_password, new_password = sys.argv[1:4]

def new_opener():
    cj = http.cookiejar.CookieJar()
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj)), cj

def csrf(cj):
    for c in cj:
        if c.name == "authentik_csrf":
            return c.value
    return None

def call(opener, cj, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    token = csrf(cj)
    if token:
        req.add_header("X-authentik-CSRF", token)
    with opener.open(req) as resp:
        return json.loads(resp.read())

def sign_in_with_password(password):
    opener, cj = new_opener()
    call(opener, cj, "GET", f"/api/v3/flows/executor/{FLOW}/?query=")
    call(opener, cj, "POST", f"/api/v3/flows/executor/{FLOW}/", {"uid_field": username})
    step = call(opener, cj, "POST", f"/api/v3/flows/executor/{FLOW}/", {"password": password})
    return opener, cj, step

# attempt 1: temp password reaches the forced-change prompt, not completion
_, _, step1 = sign_in_with_password(temp_password)
print(f"attempt1: {step1.get('component')}")

# attempt 2: same temp password, same outcome — not "invalid password"
_, _, step2 = sign_in_with_password(temp_password)
print(f"attempt2: {step2.get('component')}")

# complete the change on a third attempt
opener, cj, step3 = sign_in_with_password(temp_password)
print(f"attempt3-prompt: {step3.get('component')}")
step4 = call(opener, cj, "POST", f"/api/v3/flows/executor/{FLOW}/", {"password": new_password, "password_repeat": new_password})
print(f"attempt3-change: {step4.get('component')}")

# the temporary password is now dead
_, _, step5 = sign_in_with_password(temp_password)
print(f"temp-after-change: {step5.get('component')}")

# the new password signs straight in, no prompt
_, _, step6 = sign_in_with_password(new_password)
print(f"new-password: {step6.get('component')}")
PY
result="$(docker run --rm --network "container:${CID}" -v "${DRIVER}:/f.py:ro" \
  python:3.12-alpine python3 /f.py "$USERNAME" "$TEMP_PASSWORD" "$NEW_PASSWORD")"
rm -f "$DRIVER"
echo "$result"

if echo "$result" | grep -q "^attempt1: ak-stage-prompt$" && echo "$result" | grep -q "^attempt2: ak-stage-prompt$"; then
  echo "PASS: the temporary password reaches nothing until changed, repeatedly, the same way each time (A1b)"
else
  echo "FAILED: expected both attempts with the temporary password to land on ak-stage-prompt, got:"
  echo "$result"
  fail=1
fi

if echo "$result" | grep -q "^attempt3-change: xak-flow-redirect$"; then
  echo "PASS: completing the prompt with a new password finishes sign-in"
else
  echo "FAILED: expected the password change to complete sign-in (xak-flow-redirect)"
  fail=1
fi

if echo "$result" | grep -q "^temp-after-change: ak-stage-password$" && echo "$result" | grep -q "^new-password: xak-flow-redirect$"; then
  echo "PASS: the temporary password no longer works; the member's own new password does"
else
  echo "FAILED: expected the temporary password dead and the new password to sign in cleanly"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
