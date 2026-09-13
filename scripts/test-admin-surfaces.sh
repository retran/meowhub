#!/usr/bin/env bash
# Proves spec 0002 T10's done-when for real: a household-only member is
# refused n8n's editor and Kuma's dashboard (both admin-only, R17a), an
# admin reaches both, and one sign-in covers both surfaces (A34) — no
# second Authentik prompt, n8n's own password the one documented
# exception (R17a's table).
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
fail=0

TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token, TokenIntents, User
u = User.objects.get(username='akadmin')
tok, _ = Token.objects.get_or_create(identifier='meowhub-test-fixture', defaults={'user': u, 'intent': TokenIntents.INTENT_API, 'expiring': False})
print(tok.key)
PY
)"
HOUSEHOLD_GROUP_PK="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/groups/?name=household" | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['pk'])")"
ADMIN_GROUP_PK="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/groups/?name=admin" | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['pk'])")"

create_user() {
  local username="$1"
  local json
  json="$(bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"username\":\"${username}\",\"name\":\"${username}\",\"email\":\"${username}@example.test\",\"is_active\":true}" \
    http://localhost:9000/api/v3/core/users/)"
  local pk
  pk="$(echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin)['pk'])")"
  bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"password\":\"${PASSWORD}\"}" "http://localhost:9000/api/v3/core/users/${pk}/set_password/" >/dev/null
  bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
    -d "{\"pk\": ${pk}}" "http://localhost:9000/api/v3/core/groups/${HOUSEHOLD_GROUP_PK}/add_user/" >/dev/null
  echo "$pk"
}

MEMBER_PK="$(create_user meowhub-t10-test-member)"
ADMIN_PK="$(create_user meowhub-t10-test-admin)"
bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
  -d "{\"pk\": ${ADMIN_PK}}" "http://localhost:9000/api/v3/core/groups/${ADMIN_GROUP_PK}/add_user/" >/dev/null

cleanup() {
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/users/${MEMBER_PK}/" >/dev/null 2>&1 || true
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" "http://localhost:9000/api/v3/core/users/${ADMIN_PK}/" >/dev/null 2>&1 || true
}
trap cleanup EXIT

CA_TMP="$(mktemp)"
$COMPOSE exec -T proxy cat /data/caddy/pki/authorities/local/root.crt > "$CA_TMP"

check_surfaces() {
  local username="$1"
  python3 - "$username" "$PASSWORD" "$CA_TMP" "$PROXY_HTTPS_PORT" <<'PY'
import http.cookiejar, json, ssl, sys, urllib.error, urllib.request
from urllib.parse import urlsplit, urlunsplit

username, password, ca, port = sys.argv[1:5]
base = f"https://localhost:{port}"
netloc = f"localhost:{port}"
flow = "default-authentication-flow"

class FixRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parts = urlsplit(newurl)
        fixed = urlunsplit(("https", netloc, parts.path, parts.query, ""))
        return super().redirect_request(req, fp, code, msg, headers, fixed)

ctx = ssl.create_default_context(cafile=ca)
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx), FixRedirect()
)

def csrf():
    for c in cj:
        if c.name == "authentik_csrf":
            return c.value
    return None

def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(base + path, data=data, method=method)
    r.add_header("Content-Type", "application/json")
    r.add_header("Accept", "application/json")
    token = csrf()
    if token:
        r.add_header("X-authentik-CSRF", token)
    with opener.open(r) as resp:
        return resp.status, resp.read()

call("GET", f"/api/v3/flows/executor/{flow}/?query=")
call("POST", f"/api/v3/flows/executor/{flow}/", {"uid_field": username})
call("POST", f"/api/v3/flows/executor/{flow}/", {"password": password})

for path, label in (("/", "n8n"), ("/kuma/", "kuma")):
    try:
        with opener.open(urllib.request.Request(base + path, method="GET")) as resp:
            print(f"{label}={resp.status}")
    except urllib.error.HTTPError as e:
        print(f"{label}={e.code}")
PY
}

member_result="$(check_surfaces meowhub-t10-test-member)"
admin_result="$(check_surfaces meowhub-t10-test-admin)"
rm -f "$CA_TMP"

echo "household-only member: $member_result"
echo "admin: $admin_result"

if echo "$member_result" | grep -q "n8n=403" && echo "$member_result" | grep -q "kuma=403"; then
  echo "PASS: a household-only member is refused both admin surfaces"
else
  echo "FAILED: a household-only member should be refused both n8n and kuma, got: $member_result"
  fail=1
fi

if echo "$admin_result" | grep -q "n8n=200" && echo "$admin_result" | grep -q "kuma=200"; then
  echo "PASS: an admin reaches both surfaces with the one sign-in already completed (A34)"
else
  echo "FAILED: an admin should reach both n8n and kuma, got: $admin_result"
  fail=1
fi

license_count="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d authentik -t -A -c "select count(*) from authentik_enterprise_license;")"
if [ "$license_count" = "0" ]; then
  echo "PASS: no Authentik Enterprise license is installed anywhere (A33)"
else
  echo "FAILED: expected zero Enterprise licenses, found ${license_count}"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
