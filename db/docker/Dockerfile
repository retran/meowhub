# PostgreSQL with pgTAP installed, used identically in every environment
# (ADR 0002): the same image serves local development, CI and the deployed
# host, so "does the test suite even have its extension" is never a
# CI-only or local-only question.
FROM postgres:16

RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-16-pgtap \
    && rm -rf /var/lib/apt/lists/*
