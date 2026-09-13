#!/usr/bin/env bash
# Proves A21 for real (spec 0002 T13, R14a/b): the scaffold creates the
# first admin from SCAFFOLD_ADMIN_EMAIL/PASSWORD, they can sign in (after
# the same forced change every admin-created account goes through, T13's
# other mechanism), and a second attempt is refused outright.
set -euo pipefail

: "${SCAFFOLD_ADMIN_EMAIL:?SCAFFOLD_ADMIN_EMAIL not set}"
: "${SCAFFOLD_ADMIN_PASSWORD:?SCAFFOLD_ADMIN_PASSWORD not set}"
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
if [ "$EXISTING" != "0" ]; then
  echo "SKIPPED: a member already exists — this test only proves a genuine bootstrap (run against a clean database)"
  exit 0
fi

fail=0

FIRST_OUT="$(bash scripts/scaffold-admin.sh)"
echo "$FIRST_OUT"
ADMIN_ID="$(psql_meowhub -t -A -c "select id from member where role = 'admin' limit 1;")"

if [ -n "$ADMIN_ID" ]; then
  echo "PASS: the scaffold creates the first admin"
else
  echo "FAILED: no admin member row exists after the scaffold ran"
  fail=1
fi

USERNAME="${SCAFFOLD_ADMIN_EMAIL%%@*}"
CID="$($COMPOSE ps -q authentik-server)"
DRIVER="$(mktemp)"
cat > "$DRIVER" <<'PY'
import http.cookiejar, json, sys, urllib.request

BASE = "http://localhost:9000"
FLOW = "default-authentication-flow"
username, password = sys.argv[1:3]

cj = http.cookiejar.CookieJar()
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

call("GET", f"/api/v3/flows/executor/{FLOW}/?query=")
call("POST", f"/api/v3/flows/executor/{FLOW}/", {"uid_field": username})
step = call("POST", f"/api/v3/flows/executor/{FLOW}/", {"password": password})
print(step.get("component"))
PY
sign_in_result="$(docker run --rm --network "container:${CID}" -v "${DRIVER}:/f.py:ro" \
  python:3.12-alpine python3 /f.py "$USERNAME" "$SCAFFOLD_ADMIN_PASSWORD")"
rm -f "$DRIVER"

if [ "$sign_in_result" = "ak-stage-prompt" ]; then
  echo "PASS: the scaffolded admin signs in with the documented password, and is met with the forced password change"
else
  echo "FAILED: expected ak-stage-prompt after signing in with the scaffolded password, got: ${sign_in_result}"
  fail=1
fi

SECOND_OUTPUT=""
if SECOND_OUTPUT="$(bash scripts/scaffold-admin.sh 2>&1)"; then
  echo "FAILED: a second scaffold attempt should be refused, but it succeeded: $SECOND_OUTPUT"
  fail=1
else
  echo "PASS: a second scaffold attempt is refused outright ($SECOND_OUTPUT)"
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
