#!/usr/bin/env bash
# The first admin, once (R14a/b/c, spec 0001 T17 rewritten for spec 0002
# T13): scripts/create-member.sh already refuses on its own once any
# member exists, and its bootstrap branch is exactly this scaffold — this
# wrapper only supplies the environment variables R14a names and is the
# one command a fresh deployment is documented to run.
set -euo pipefail

: "${SCAFFOLD_ADMIN_EMAIL:?SCAFFOLD_ADMIN_EMAIL not set}"
: "${SCAFFOLD_ADMIN_PASSWORD:?SCAFFOLD_ADMIN_PASSWORD not set}"

bash scripts/create-member.sh admin "$SCAFFOLD_ADMIN_EMAIL"
