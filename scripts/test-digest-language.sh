#!/usr/bin/env bash
# Proves spec 0004 A12/R12: a digest carries no advice, no judgement and
# no accounting vocabulary.
#
# The check runs against the digest **templates themselves**, not
# against a rendered sample: a sample only proves what one period
# happened to say, whereas the template is every digest that will ever
# be sent. The forbidden list is committed alongside them
# (i18n/digest-forbidden-words.json) so adding a word to a template and
# a word to the list is a visible, reviewable pair.
set -euo pipefail

fail=0

for lang in en ru; do
  templates="$(jq -r 'to_entries[] | select(.key | startswith("digest_")) | .value' "i18n/${lang}.json")"
  if [ -z "$templates" ]; then
    echo "FAILED: no digest templates in i18n/${lang}.json"
    fail=1
    continue
  fi

  lowered="$(printf '%s' "$templates" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r word; do
    if printf '%s' "$lowered" | grep -qF "$word"; then
      echo "FAILED: the ${lang} digest templates contain the forbidden word '${word}'"
      fail=1
    fi
  done < <(jq -r 'to_entries[] | select(.key != "_why") | .value[]' i18n/digest-forbidden-words.json | tr '[:upper:]' '[:lower:]')
done

# The check itself must be able to fail, or it proves nothing: a
# template carrying a forbidden word is rejected.
probe="$(printf '%s' "you should consider spending less" | tr '[:upper:]' '[:lower:]')"
caught=0
while IFS= read -r word; do
  if printf '%s' "$probe" | grep -qF "$word"; then caught=1; fi
done < <(jq -r 'to_entries[] | select(.key != "_why") | .value[]' i18n/digest-forbidden-words.json | tr '[:upper:]' '[:lower:]')
if [ "$caught" != "1" ]; then
  echo "FAILED: the forbidden-word check does not catch a sentence made of forbidden words"
  fail=1
fi

if [ "$fail" != "0" ]; then
  exit 1
fi
echo "PASS: the digest templates carry no accounting vocabulary, no advice and no judgement, in either language (A12, R12)"
