#!/usr/bin/env bash
# Proves T8/R18: a missing key fails visibly, and the two catalogues never
# drift apart silently — a key present in one language and not the other is
# exactly how a slug ends up on screen.
set -euo pipefail

fail=0

# 1. a real key resolves in both languages
scripts/i18n.sh ru health_check_reply >/dev/null || { echo "FAILED: ru health_check_reply"; fail=1; }
scripts/i18n.sh en health_check_reply >/dev/null || { echo "FAILED: en health_check_reply"; fail=1; }

# 2. variable substitution actually substitutes
out="$(scripts/i18n.sh en backup_failure reason=timeout)"
if [[ "$out" != *"timeout"* ]] || [[ "$out" == *"{{reason}}"* ]]; then
  echo "FAILED: substitution did not apply — got: $out"; fail=1
fi

# 3. a missing key fails loudly, not silently
if scripts/i18n.sh ru this_key_does_not_exist >/dev/null 2>/tmp/i18n-err; then
  echo "FAILED: missing key did not fail"; fail=1
else
  grep -q "missing key" /tmp/i18n-err || { echo "FAILED: failure message unclear"; fail=1; }
fi

# 4. the two catalogues carry exactly the same keys — no drift
ru_keys="$(jq -r 'keys[]' i18n/ru.json | sort)"
en_keys="$(jq -r 'keys[]' i18n/en.json | sort)"
if [ "$ru_keys" != "$en_keys" ]; then
  echo "FAILED: ru.json and en.json have different keys"
  diff <(echo "$ru_keys") <(echo "$en_keys")
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "i18n tests FAILED"
  exit 1
fi
echo "i18n tests PASSED"
