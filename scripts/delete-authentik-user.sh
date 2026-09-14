#!/usr/bin/env bash
# Removes an Authentik user by username, for test fixtures only.
#
# A member created by scripts/create-member.sh exists in two places: a
# row in `member` and a user in Authentik (ADR 0032). A test that
# deletes only the row leaves the Authentik user behind, and the next
# run of the same test fails on "username must be unique" -- which
# reads as a broken feature rather than as leftover state. Nothing in
# the product deletes a person; deactivation is the real operation
# (scripts/deactivate-member.sh). This is for a fixture's own cleanup.
set -euo pipefail

USERNAME="${1:?usage: delete-authentik-user.sh <username>}"

TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token, TokenIntents, User
u = User.objects.get(username='akadmin')
tok, _ = Token.objects.get_or_create(identifier='meowhub-create-member-fixture', defaults={'user': u, 'intent': TokenIntents.INTENT_API, 'expiring': False})
print(tok.key)
PY
)"

PKS="$(bash scripts/authentik-curl.sh -sS -H "Authorization: Bearer ${TOKEN}" \
  "http://localhost:9000/api/v3/core/users/?search=${USERNAME}" \
  | python3 -c "
import json, sys
wanted = sys.argv[1]
print(' '.join(str(r['pk']) for r in json.load(sys.stdin).get('results', []) if r.get('username') == wanted))
" "$USERNAME")"

for pk in $PKS; do
  bash scripts/authentik-curl.sh -sS -o /dev/null -X DELETE -H "Authorization: Bearer ${TOKEN}" \
    "http://localhost:9000/api/v3/core/users/${pk}/"
done
