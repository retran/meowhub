#!/usr/bin/env bash
# Waits until n8n is not just healthy but actually serving webhooks.
#
# n8n reports healthy as soon as its HTTP server is up, which is a
# moment before it has re-registered the webhook paths of every active
# workflow. A test that posts in that gap gets a 404 and reads it as the
# behaviour being wrong -- which is how a green suite turns red for no
# reason at all. The health-check workflow (spec 0001) is always active,
# so its own webhook answering is the honest signal that the others are
# registered too.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"
ATTEMPTS="${1:-40}"

for _ in $(seq 1 "$ATTEMPTS"); do
  if [ "$($COMPOSE ps n8n --format '{{.Health}}' 2>/dev/null)" = "healthy" ] \
     && $COMPOSE exec -T n8n wget -q -O- http://localhost:5678/webhook/health-check >/dev/null 2>&1; then
    # health-check answering says registration has begun, not that it has
    # finished: the workflows are activated one after another, and a test's
    # own entry workflow is usually the last of them. A second is enough
    # for the rest of the list, and cheap next to a false failure.
    sleep 2
    exit 0
  fi
  sleep 2
done

echo "n8n did not start serving webhooks in time" >&2
exit 1
