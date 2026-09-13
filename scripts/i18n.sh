#!/usr/bin/env bash
# Looks up a message-catalogue key (ADR 0017, spec 0001 T8/R18). A missing
# key fails visibly — never renders as a blank string or a bare slug.
#
# Usage: i18n.sh <lang> <key> [name=value ...]
set -euo pipefail

LANG_CODE="${1:?usage: i18n.sh <lang: ru|en> <key> [name=value ...]}"
KEY="${2:?a key is required}"
shift 2

CATALOGUE="i18n/${LANG_CODE}.json"
SENTINEL="__I18N_MISSING_KEY__"

if [ ! -f "$CATALOGUE" ]; then
  echo "i18n: no catalogue for language '${LANG_CODE}' (expected ${CATALOGUE})" >&2
  exit 1
fi

VALUE="$(jq -r --arg k "$KEY" --arg sentinel "$SENTINEL" 'if has($k) then .[$k] else $sentinel end' "$CATALOGUE")"
if [ "$VALUE" = "$SENTINEL" ]; then
  echo "i18n: missing key '${KEY}' in ${CATALOGUE}" >&2
  exit 1
fi

for pair in "$@"; do
  name="${pair%%=*}"
  val="${pair#*=}"
  VALUE="${VALUE//\{\{$name\}\}/$val}"
done

echo "$VALUE"
