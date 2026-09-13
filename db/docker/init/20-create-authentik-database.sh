#!/bin/bash
# Authentik gets its own database, never meowhub's (ADR 0004) — same
# reasoning and same pattern as 10-create-n8n-database.sh. Runs once, only
# on a brand-new data directory.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE authentik;
EOSQL
