#!/usr/bin/env bash
# Proves spec 0004 A5b/R2a: every view in the database that produces a
# figure has a read tool in tools/*.json, or is a documented exemption
# below -- so a later slice that adds a view and forgets to make it
# askable in chat is a failing check, not a silent gap.
set -euo pipefail

: "${POSTGRES_SUPERUSER:?POSTGRES_SUPERUSER not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"

COMPOSE="docker compose -f compose.yaml"

# Reference/structural data and internal plumbing -- not a reporting
# figure in R2's sense, so no tool answers a question about them
# directly. Each exemption is deliberate, not a place to hide a gap:
#   v_account               -- the chart itself; a picker, not a figure
#   v_category              -- the category list; a picker, not a figure
#   v_period_reconciliation -- surfaced as a field on other tools' own
#                              replies (R17), not a standalone question
#   v_reporting_period      -- ADR 0045's own internal period
#                              resolution, never asked about directly
EXEMPT_VIEWS="v_account v_category v_period_reconciliation v_reporting_period"

VIEWS="$($COMPOSE exec -T postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -t -A -c \
  "select table_name from information_schema.views where table_schema='public' order by table_name;")"

TOOL_PURPOSES="$(for f in tools/*.json; do
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('purpose',''))" "$f"
done)"

fail=0
for view in $VIEWS; do
  is_exempt=false
  for exempt in $EXEMPT_VIEWS; do
    [ "$view" = "$exempt" ] && is_exempt=true && break
  done
  if $is_exempt; then
    continue
  fi
  if ! echo "$TOOL_PURPOSES" | grep -qE "\b${view}\b"; then
    echo "FAILED: $view has no read tool naming it, and is not a documented exemption (A5b)"
    fail=1
  fi
done

if [ "$fail" = "0" ]; then
  echo "PASS: every non-exempt view has a read tool naming it (A5b)"
fi

# Read tools the agent uses to make a decision rather than to answer a
# member's question (ADR 0046). A member never asks find_merchant --
# the agent calls it to work out whether a shop is one we already know
# before deciding to create it. They are not part of R23's contract,
# which is about what a member can ask and therefore what R6 may refuse.
EXEMPT_TOOLS="find_merchant find_category find_account find_recent_transaction transaction_lines"

# The documented list of answerable QUESTIONS must match the read-only
# tools in the registry (R23, R2's own scope) -- a mutating action
# tool (record_transaction, undo_last_action, ...) is a capability,
# not an answerable question, and is documented in the earlier
# sections of the guide instead.
missing_from_docs=0
for f in tools/*.json; do
  mutating="$(python3 -c "import json; print(json.load(open('$f')).get('mutating', True))" "$f")"
  [ "$mutating" = "True" ] && continue
  name="$(python3 -c "import json; print(json.load(open('$f'))['name'])" "$f")"
  tool_exempt=false
  for exempt in $EXEMPT_TOOLS; do
    [ "$name" = "$exempt" ] && tool_exempt=true && break
  done
  $tool_exempt && continue
  if ! grep -qE "\b${name}\b" docs/guides/talking-to-meow.md 2>/dev/null; then
    echo "FAILED: read tool '$name' is not mentioned in docs/guides/talking-to-meow.md (R23)"
    missing_from_docs=1
  fi
done
if [ "$missing_from_docs" = "0" ]; then
  echo "PASS: every declared tool is named in docs/guides/talking-to-meow.md (R23)"
fi

if [ "$fail" != "0" ] || [ "$missing_from_docs" != "0" ]; then
  exit 1
fi
