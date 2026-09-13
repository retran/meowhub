#!/usr/bin/env bash
# Writes the token bridge's Authentik API token into .env once, the first
# time the service account exists (spec 0002 T10). The blueprint
# (authentik/blueprints/04-token-bridge-account.yaml) creates the token but
# cannot choose its literal value — Authentik generates that — so this is
# the same "generated credential written back to .env" pattern as
# scripts/configure-monitoring.sh's push URLs. Requires authentik-server to
# already be up and to have applied its blueprints (it does so on boot).
set -euo pipefail

# The worker applies blueprints asynchronously, on a file-change watch — not
# synchronously as part of its own healthcheck — so a freshly-started
# worker can take a few seconds to have applied 04-token-bridge-account.yaml
# even though the file was already there when it booted. Poll rather than
# assume either instant availability or failure.
TOKEN=""
for _ in $(seq 1 30); do
  TOKEN="$(bash scripts/authentik-shell.sh <<'PY'
from authentik.core.models import Token
t = Token.objects.filter(identifier='meowhub-token-bridge-api-token').first()
print(t.key if t else "")
PY
)"
  [ -n "$TOKEN" ] && break
  sleep 1
done

if [ -z "$TOKEN" ]; then
  echo "the token bridge service account's token does not exist yet (blueprint not applied?)" >&2
  exit 1
fi

if [ -f .env ]; then
  if grep -q "^AUTHENTIK_API_TOKEN=" .env; then
    sed -i.bak "s#^AUTHENTIK_API_TOKEN=.*#AUTHENTIK_API_TOKEN=${TOKEN}#" .env
    rm -f .env.bak
  else
    echo "AUTHENTIK_API_TOKEN=${TOKEN}" >> .env
  fi
  echo "wrote AUTHENTIK_API_TOKEN to .env"
fi
