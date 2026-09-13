#!/bin/bash
# n8n gets its own database, never meowhub's (ADR 0004: the household ledger
# must survive replacing n8n, so its schema is never mixed with the
# platform's own tables). Runs once, only on a brand-new data directory —
# the official postgres image's own init-script convention.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE n8n;
EOSQL
