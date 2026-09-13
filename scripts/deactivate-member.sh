#!/usr/bin/env bash
# A departure is a designed event (ADR 0026, spec 0002 A17): the member
# row stays (attribution never breaks), but access is withdrawn
# immediately — the Authentik account disabled, every session it holds
# ended right now rather than left to expire, and its passkeys revoked.
# Admin-only, like every other change to a member's account.
#
# Usage: scripts/deactivate-member.sh <admin_member_id> <member_id>
set -euo pipefail

: "${PGRST_JWT_SECRET:?PGRST_JWT_SECRET not set}"

ADMIN_MEMBER_ID="${1:?usage: deactivate-member.sh <admin_member_id> <member_id>}"
MEMBER_ID="${2:?usage: deactivate-member.sh <admin_member_id> <member_id>}"

COMPOSE="docker compose -f compose.yaml"
TOKEN="$(bash scripts/mint-local-jwt.sh hh_admin "$ADMIN_MEMBER_ID")"
CID_POSTGREST="$($COMPOSE ps -q postgrest)"

# member.active = false, the row itself untouched otherwise (R10/ADR 0026).
status="$(docker run --rm --network "container:${CID_POSTGREST}" curlimages/curl:8.11.1 -sS -o /dev/null -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
  -d '{"active": false}' "http://localhost:3000/member?id=eq.${MEMBER_ID}")"
if [ "$status" != "204" ]; then
  echo "FAILED to deactivate member ${MEMBER_ID} (${status})" >&2
  exit 1
fi

SUBJECT="$(docker run --rm --network "container:${CID_POSTGREST}" curlimages/curl:8.11.1 -sS \
  -H "Authorization: Bearer ${TOKEN}" "http://localhost:3000/member_identity?member_id=eq.${MEMBER_ID}&select=provider_subject" \
  | python3 -c "import json,sys; r=json.load(sys.stdin); print(r[0]['provider_subject'] if r else '')")"

if [ -z "$SUBJECT" ]; then
  echo "deactivated member ${MEMBER_ID} (no identity provider link to revoke)"
  exit 0
fi

AKADMIN_TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token, TokenIntents, User
u = User.objects.get(username='akadmin')
tok, _ = Token.objects.get_or_create(identifier='meowhub-create-member-fixture', defaults={'user': u, 'intent': TokenIntents.INTENT_API, 'expiring': False})
print(tok.key)
PY
)"

# Authentik's user-list API has no filter for "uid" (the same limitation
# the token bridge already works around) — filter the full list
# client-side, fine at household scale.
USER_JSON="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${AKADMIN_TOKEN}" "http://localhost:9000/api/v3/core/users/" \
  | python3 -c "
import json, sys
users = json.load(sys.stdin)['results']
for u in users:
    if u['uid'] == sys.argv[1]:
        print(json.dumps(u))
        break
" "$SUBJECT")"

if [ -z "$USER_JSON" ]; then
  echo "deactivated member ${MEMBER_ID} (its identity provider account was not found)"
  exit 0
fi
AUTHENTIK_PK="$(echo "$USER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['pk'])")"
AUTHENTIK_USERNAME="$(echo "$USER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['username'])")"

bash scripts/authentik-curl.sh -sS -X PATCH -H "Authorization: Bearer ${AKADMIN_TOKEN}" -H 'Content-Type: application/json' \
  -d '{"is_active": false}' "http://localhost:9000/api/v3/core/users/${AUTHENTIK_PK}/" >/dev/null

# End every session this account currently holds — disabling is_active
# alone does not invalidate a cookie already issued (A17: "existing
# sessions do not survive").
SESSIONS="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${AKADMIN_TOKEN}" \
  "http://localhost:9000/api/v3/core/authenticated_sessions/?user__username=${AUTHENTIK_USERNAME}" \
  | python3 -c "import json,sys; print('\n'.join(r['uuid'] for r in json.load(sys.stdin)['results']))")"
while IFS= read -r session_uuid; do
  [ -z "$session_uuid" ] && continue
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${AKADMIN_TOKEN}" \
    "http://localhost:9000/api/v3/core/authenticated_sessions/${session_uuid}/" >/dev/null
done <<< "$SESSIONS"

# Revoke its passkeys too (ADR 0026).
DEVICES="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${AKADMIN_TOKEN}" \
  "http://localhost:9000/api/v3/authenticators/webauthn/?user=${AUTHENTIK_PK}" \
  | python3 -c "import json,sys; print('\n'.join(str(r['pk']) for r in json.load(sys.stdin)['results']))" 2>/dev/null || true)"
while IFS= read -r device_pk; do
  [ -z "$device_pk" ] && continue
  bash scripts/authentik-curl.sh -sS -X DELETE -H "Authorization: Bearer ${AKADMIN_TOKEN}" \
    "http://localhost:9000/api/v3/authenticators/webauthn/${device_pk}/" >/dev/null
done <<< "$DEVICES"

echo "deactivated member ${MEMBER_ID}: Authentik account disabled, sessions ended, passkeys revoked"
