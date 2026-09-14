#!/usr/bin/env bash
# Proves A17 for real (ADR 0026, spec 0002 T13): a deactivated member's
# sign-in fails outright, and a session already established before
# deactivation does not survive it either.
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

ADMIN_ID="$(psql_meowhub -t -A -c "select id from member where role = 'admin' limit 1;")"
if [ -z "$ADMIN_ID" ]; then
  echo "SKIPPED: no admin member exists yet (run scripts/scaffold-admin.sh first)"
  exit 0
fi

PASSWORD="CorrectHorseBattery3!"
CREATE_OUT="$(bash scripts/create-member.sh member deactivation-test@example.test "$ADMIN_ID")"
MEMBER_ID="$(echo "$CREATE_OUT" | grep -o 'member [0-9]*' | grep -o '[0-9]*' | head -1)"
TEMP_PASSWORD="$(echo "$CREATE_OUT" | sed -n 's/^temporary password: //p')"
USERNAME="deactivation-test"

WORKDIR="$(mktemp -d)"
cleanup() {
  psql_meowhub -c "
    select set_config('meowhub.actor', 'test-suite', true);
    delete from member_identity where member_id = ${MEMBER_ID};
    delete from member where id = ${MEMBER_ID};
  " >/dev/null 2>&1 || true
  # The fixture exists in Authentik too, and a user left behind there
  # makes the next run of this test fail on a unique username rather
  # than on anything it is testing.
  bash scripts/delete-authentik-user.sh deactivation-test >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

CID="$($COMPOSE ps -q authentik-server)"
cat > "$WORKDIR/driver.py" <<'PY'
import http.cookiejar, json, sys, urllib.request

BASE = "http://localhost:9000"
FLOW = "default-authentication-flow"
phase, username, jar_path = sys.argv[1:4]

cj = http.cookiejar.MozillaCookieJar(jar_path)
if phase == "after":
    cj.load(ignore_discard=True, ignore_expires=True)
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

def csrf():
    for c in cj:
        if c.name == "authentik_csrf":
            return c.value
    return None

def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    token = csrf()
    if token:
        req.add_header("X-authentik-CSRF", token)
    with opener.open(req) as resp:
        return json.loads(resp.read())

if phase == "establish":
    temp_password, new_password = sys.argv[4:6]
    call("GET", f"/api/v3/flows/executor/{FLOW}/?query=")
    call("POST", f"/api/v3/flows/executor/{FLOW}/", {"uid_field": username})
    call("POST", f"/api/v3/flows/executor/{FLOW}/", {"password": temp_password})
    step = call("POST", f"/api/v3/flows/executor/{FLOW}/", {"password": new_password, "password_repeat": new_password})
    print(f"established: {step.get('component')}")
    whoami = call("GET", "/api/v3/core/users/me/")
    print(f"whoami-before: {whoami.get('user', {}).get('username')}")
    for c in cj:
        c.discard = False
    cj.save(ignore_discard=True, ignore_expires=True)
elif phase == "after":
    try:
        whoami = call("GET", "/api/v3/core/users/me/")
        print(f"whoami-after: {whoami.get('user', {}).get('username', 'anonymous')}")
    except urllib.error.HTTPError as e:
        print(f"whoami-after: http-error-{e.code}")
    new_password = sys.argv[4]
    fresh_cj = http.cookiejar.CookieJar()
    fresh_opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(fresh_cj))
    def fresh_call(method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(BASE + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("Accept", "application/json")
        for c in fresh_cj:
            if c.name == "authentik_csrf":
                req.add_header("X-authentik-CSRF", c.value)
        with fresh_opener.open(req) as resp:
            return json.loads(resp.read())
    fresh_call("GET", f"/api/v3/flows/executor/{FLOW}/?query=")
    fresh_call("POST", f"/api/v3/flows/executor/{FLOW}/", {"uid_field": username})
    step = fresh_call("POST", f"/api/v3/flows/executor/{FLOW}/", {"password": new_password})
    print(f"signin-after: {step.get('component')}")
PY

docker run --rm --network "container:${CID}" -v "${WORKDIR}:/w" python:3.12-alpine \
  python3 /w/driver.py establish "$USERNAME" /w/cookies.txt "$TEMP_PASSWORD" "$PASSWORD"

bash scripts/deactivate-member.sh "$ADMIN_ID" "$MEMBER_ID"

result="$(docker run --rm --network "container:${CID}" -v "${WORKDIR}:/w" python:3.12-alpine \
  python3 /w/driver.py after "$USERNAME" /w/cookies.txt "$PASSWORD")"
echo "$result"

fail=0
if echo "$result" | grep -q "^whoami-after: anonymous$" || echo "$result" | grep -q "^whoami-after: http-error-"; then
  echo "PASS: the session established before deactivation does not survive it"
else
  echo "FAILED: the existing session should not survive deactivation, got: $result"
  fail=1
fi

if echo "$result" | grep -q "^signin-after: ak-stage-access-denied$" || echo "$result" | grep -q "^signin-after: ak-stage-password$"; then
  echo "PASS: a fresh sign-in attempt with the correct password fails outright once deactivated"
else
  echo "FAILED: a fresh sign-in should fail for a deactivated member, got: $result"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
