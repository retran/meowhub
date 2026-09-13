#!/usr/bin/env bash
# The one way a member's account comes to exist (R1, R14a): an admin runs
# this, never self-service (R6c's same boundary). Creates the Authentik
# account and the member/member_identity rows together, with a temporary
# password the account is locked to changing at first sign-in (R1d) —
# authentik/blueprints/05-forced-password-change.yaml is what actually
# enforces that at sign-in time; this script only sets it up.
#
# The very first account ever (member has no rows yet) is the scaffold
# (R14a/b): no admin exists yet to attribute it to, so it writes directly
# with a fixed bootstrap actor and refuses outright once any member
# exists, rather than asking for an admin id that cannot exist yet.
# Every account after that is attributed to a real, named admin.
#
# Usage:
#   scripts/create-member.sh admin <email>                    (bootstrap: first account only)
#   scripts/create-member.sh <role> <email> <admin_member_id>  (every account after)
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"
: "${PGRST_JWT_SECRET:?PGRST_JWT_SECRET not set}"

ROLE="${1:?usage: create-member.sh <role> <email> [admin_member_id]}"
EMAIL="${2:?usage: create-member.sh <role> <email> [admin_member_id]}"
ADMIN_MEMBER_ID="${3:-}"

if [ "$ROLE" != "admin" ] && [ "$ROLE" != "member" ]; then
  echo "role must be 'admin' or 'member', got: ${ROLE}" >&2
  exit 1
fi

COMPOSE="docker compose -f compose.yaml"
psql_meowhub() {
  $COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" "$@"
}

EXISTING_MEMBERS="$(psql_meowhub -t -A -c "select count(*) from member;")"
BOOTSTRAP=0
if [ "$EXISTING_MEMBERS" = "0" ]; then
  BOOTSTRAP=1
  if [ "$ROLE" != "admin" ]; then
    echo "the first account must be an admin, got: ${ROLE}" >&2
    exit 1
  fi
else
  : "${ADMIN_MEMBER_ID:?an admin_member_id is required once any account exists (R14b) — usage: create-member.sh <role> <email> <admin_member_id>}"
fi

if [ "$BOOTSTRAP" = "1" ] && [ -n "${SCAFFOLD_ADMIN_PASSWORD:-}" ]; then
  # R14a: the scaffold's password comes from the environment, not a
  # generated one nobody chose — every account after it gets a generated
  # temporary password instead, an admin's own act of creating it.
  PASSWORD="$SCAFFOLD_ADMIN_PASSWORD"
else
  PASSWORD="$(python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20)))')"
fi
USERNAME="${EMAIL%%@*}"

AKADMIN_TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token, TokenIntents, User
u = User.objects.get(username='akadmin')
tok, _ = Token.objects.get_or_create(identifier='meowhub-create-member-fixture', defaults={'user': u, 'intent': TokenIntents.INTENT_API, 'expiring': False})
print(tok.key)
PY
)"

CREATE_JSON="$(bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${AKADMIN_TOKEN}" -H 'Content-Type: application/json' \
  -d "{\"username\":\"${USERNAME}\",\"name\":\"${USERNAME}\",\"email\":\"${EMAIL}\",\"is_active\":true}" \
  http://localhost:9000/api/v3/core/users/)"
AUTHENTIK_PK="$(echo "$CREATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['pk'])")"
AUTHENTIK_UID="$(echo "$CREATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['uid'])")"

bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${AKADMIN_TOKEN}" -H 'Content-Type: application/json' \
  -d "{\"password\":\"${PASSWORD}\"}" "http://localhost:9000/api/v3/core/users/${AUTHENTIK_PK}/set_password/" >/dev/null

CHANGE_DATE="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${AKADMIN_TOKEN}" "http://localhost:9000/api/v3/core/users/${AUTHENTIK_PK}/" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['password_change_date'])")"
bash scripts/authentik-curl.sh -sS -X PATCH -H "Authorization: Bearer ${AKADMIN_TOKEN}" -H 'Content-Type: application/json' \
  -d "{\"attributes\": {\"password_set_by_admin_at\": \"${CHANGE_DATE}\"}}" \
  "http://localhost:9000/api/v3/core/users/${AUTHENTIK_PK}/" >/dev/null

# The household group (R7) puts the new account somewhere sane by
# default; an admin promotes with the admin group separately if the role
# calls for it — group membership and the member.role column are kept in
# step by whoever links, the same as any other admin action here.
GROUP_NAME="household"
[ "$ROLE" = "admin" ] && GROUP_NAME="admin"
GROUP_PK="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${AKADMIN_TOKEN}" "http://localhost:9000/api/v3/core/groups/?name=${GROUP_NAME}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['pk'])")"
bash scripts/authentik-curl.sh -sS -X POST -H "Authorization: Bearer ${AKADMIN_TOKEN}" -H 'Content-Type: application/json' \
  -d "{\"pk\": ${AUTHENTIK_PK}}" "http://localhost:9000/api/v3/core/groups/${GROUP_PK}/add_user/" >/dev/null

if [ "$BOOTSTRAP" = "1" ]; then
  MEMBER_ID="$(psql_meowhub -t -A -c "
    select set_config('meowhub.actor', 'bootstrap-scaffold', true);
    insert into member (role) values ('${ROLE}') returning id;
  " | grep -E '^[0-9]+$' | tail -1)"
  psql_meowhub -c "
    select set_config('meowhub.actor', 'bootstrap-scaffold', true);
    insert into member_identity (member_id, provider_subject) values (${MEMBER_ID}, '${AUTHENTIK_UID}');
  " >/dev/null
  echo "bootstrap: created the first admin (member ${MEMBER_ID})"
else
  TOKEN="$(bash scripts/mint-local-jwt.sh hh_admin "$ADMIN_MEMBER_ID")"
  CID="$($COMPOSE ps -q postgrest)"
  member_response="$(docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 -sS -w '\nSTATUS:%{http_code}' \
    -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
    -d "{\"role\": \"${ROLE}\"}" http://localhost:3000/member)"
  member_status="${member_response##*STATUS:}"
  member_body="${member_response%$'\n'STATUS:*}"
  if [ "$member_status" != "201" ]; then
    echo "FAILED to create member (${member_status}): ${member_body}" >&2
    exit 1
  fi
  MEMBER_ID="$(echo "$member_body" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")"

  identity_response="$(docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 -sS -w '\nSTATUS:%{http_code}' \
    -X POST -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' -H 'Prefer: return=minimal' \
    -d "{\"member_id\": ${MEMBER_ID}, \"provider_subject\": \"${AUTHENTIK_UID}\"}" http://localhost:3000/member_identity)"
  identity_status="${identity_response##*STATUS:}"
  if [ "$identity_status" != "201" ]; then
    echo "FAILED to link identity (${identity_status})" >&2
    exit 1
  fi
  echo "created member ${MEMBER_ID} (role: ${ROLE}), by admin ${ADMIN_MEMBER_ID}"
fi

echo "email: ${EMAIL}"
echo "temporary password: ${PASSWORD}"
echo "(must be changed at first sign-in — the account reaches nothing until then)"
