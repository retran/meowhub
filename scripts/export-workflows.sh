#!/usr/bin/env bash
# Exports every n8n workflow to workflows/ in this repository (ADR 0010).
# Run after any change made in the editor; a workflow is not "done" until
# its export is committed. Uses the n8n CLI inside the running container,
# so this is what "configuration as code" actually means for n8n — there is
# no native git sync in the community edition.
set -euo pipefail

COMPOSE="docker compose -f compose.yaml"

# Clear the container-side directory first: n8n writes into it without
# clearing it, so a workflow deleted from n8n would leave its last
# export behind and be copied back into this repository on every run —
# silently undoing the deletion, and invisible to drift detection
# because both sides would then agree.
$COMPOSE exec -T n8n rm -rf /tmp/workflow-export
$COMPOSE exec -T n8n n8n export:workflow --all --separate --output=/tmp/workflow-export --pretty >&2
rm -rf /tmp/meowhub-workflow-export
mkdir -p /tmp/meowhub-workflow-export
docker compose cp n8n:/tmp/workflow-export/. /tmp/meowhub-workflow-export/ >&2

# Strip what a fresh import always regenerates or mutates at runtime — none
# of it is configuration, and committing it would make every export look
# like a change even when nothing meaningful moved (the same set
# scripts/detect-drift.sh ignores when comparing).
clean='
import json, sys
d = json.load(open(sys.argv[1]))
for key in (
    "updatedAt", "createdAt", "versionId", "activeVersionId", "shared",
    "triggerCount", "staticData", "versionMetadata", "isArchived",
    "nodeGroups", "tags", "versionCounter",
):
    d.pop(key, None)
# telegram-poll and telegram-webhook are committed inactive by design: the
# delivery mode toggles exactly one of them at runtime
# (scripts/apply-telegram-mode.sh, ADR 0033), so whichever happens to be
# live at export time must never leak into the committed file.
if d["name"] in ("telegram-poll", "telegram-webhook"):
    d["active"] = False
print(json.dumps(d, indent=2, sort_keys=True))
'

for f in /tmp/meowhub-workflow-export/*.json; do
  name="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$f")"
  python3 -c "$clean" "$f" > "workflows/${name}.json"
  echo "exported: ${name}.json"
done
