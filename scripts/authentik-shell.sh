#!/usr/bin/env bash
# Runs Python against Authentik's own Django shell (spec 0002) — used for
# the handful of things its REST API does not expose (minting a token for
# the bootstrap admin, mainly). Usage: scripts/authentik-shell.sh <<< '<code>'
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
$COMPOSE exec -T authentik-server ak shell -c "$(cat)" 2>/dev/null | tail -1
