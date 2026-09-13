#!/usr/bin/env bash
# curl against Authentik's API from a container sharing its network
# namespace (spec 0002 T5) — authentik-server has neither curl nor wget of
# its own, and is not published to the host (spec 0001 T11), so this is
# the same "borrow the target's network namespace" trick as
# scripts/kuma-run.sh and scripts/restic-run.sh.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
CID="$($COMPOSE ps -q authentik-server)"

docker run --rm --network "container:${CID}" curlimages/curl:8.11.1 "$@"
