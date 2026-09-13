#!/usr/bin/env bash
# Compares the running n8n configuration against what is committed in
# workflows/, and reports a difference (ADR 0010, ADR 0020). Silence means
# "in sync"; any diff is drift that should have been exported and committed.
# On success, pushes the heartbeat last — after verification, per ADR 0020 —
# so a push never reports success falsely.
set -euo pipefail

: "${HEARTBEAT_DRIFT_CHECK_URL:?HEARTBEAT_DRIFT_CHECK_URL not set (spec 0001 T13, ADR 0020)}"

COMPOSE="docker compose -f compose.yaml"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

$COMPOSE exec -T n8n rm -rf /tmp/drift-check
$COMPOSE exec -T n8n n8n export:workflow --all --separate --output=/tmp/drift-check --pretty >&2
docker compose cp n8n:/tmp/drift-check/. "$TMP_DIR/" >&2

drifted=0
drift_report=""
for f in "$TMP_DIR"/*.json; do
  name="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$f")"
  committed="workflows/${name}.json"
  if [ ! -f "$committed" ]; then
    echo "DRIFT: ${name} exists in n8n but is not committed"
    drift_report="${drift_report}${name}: exists in n8n but is not committed"$'\n'
    drifted=1
    continue
  fi
  # Compare structural content only. Excluded, and why:
  # - timestamps, version ids, per-instance sharing/project metadata, and
  #   n8n's own bookkeeping fields: regenerated on every import, never
  #   committed to a hand-authored workflow file.
  # - staticData: runtime state (the dedup set, the poll offset) that is
  #   supposed to change on every execution — not configuration.
  # - active: the delivery mode toggles exactly one of telegram-poll and
  #   telegram-webhook at runtime (ADR 0033); both are committed inactive by
  #   design, so this is the one field expected to differ, not drift.
  strip='
import json, sys
d = json.load(open(sys.argv[1]))
for key in (
    "updatedAt", "createdAt", "versionId", "activeVersionId", "shared",
    "triggerCount", "staticData", "versionMetadata", "isArchived",
    "nodeGroups", "tags", "versionCounter", "active",
):
    d.pop(key, None)
print(json.dumps(d, sort_keys=True))
'
  a="$(python3 -c "$strip" "$f")"
  b="$(python3 -c "$strip" "$committed")"
  if [ "$a" != "$b" ]; then
    echo "DRIFT: ${name} differs from workflows/${name}.json"
    drift_report="${drift_report}${name}: differs from the committed file"$'\n'
    drifted=1
  fi
done

if [ "$drifted" -ne 0 ]; then
  echo "drift detected — run 'task export' and commit the result"
  bash scripts/telegram-report.sh "Meow: configuration drift detected —"$'\n'"${drift_report}Run task export and commit the result." || true
  exit 1
fi
bash scripts/heartbeat-curl.sh "$HEARTBEAT_DRIFT_CHECK_URL"
echo "no drift"
