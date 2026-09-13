---
id: 0004
title: PostgreSQL as the system of record
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0004 — PostgreSQL as the system of record

## Context

The ledger is the asset. Workflows, prompts and even the platform are
replaceable; years of household expenses are not. Where that data lives, and in
what shape, outlives every other decision in this project.

n8n already requires PostgreSQL for its own state (ADR 0001), so a database is
present either way. The question is whether the ledger lives there too, in a
schema we own, or somewhere else.

The system must also recognise merchants automatically and learn new ones: a
statement line reading `ALBERT HEIJN 1234 AMSTERDAM` and a typed "albert heijn"
must land on the same merchant, and an unseen merchant must become a known one
without the owner editing anything by hand.

## Decision

**PostgreSQL is the system of record.** It holds the ledger, the household
members, the merchant registry, the message log and imported statements, in a
schema we design and migrate deliberately — in its own database, separate from
the one n8n uses for its internal state.

The *shape* of the ledger is decided separately, in ADR 0011: it is double-entry,
with a chart of accounts. This ADR decides where the data lives and who owns the
schema; ADR 0011 decides what the rows mean. ADR 0012 keeps budgets, commitments
and plans in their own tables, out of the ledger.

The schema is owned, not inferred:

- **Migrations are versioned SQL files in this repository**, applied in order.
  No schema changes made by clicking in a UI.
- **The ledger is append-friendly**: a correction is a new state with history
  retained, never a silent overwrite, because an AI-guessed transaction will be
  corrected often (vision principle 8).
- **Every transaction records its provenance**: which member submitted it, in
  which form (text, photo, voice, statement), and which model parsed it, if any.
- **Invariants are enforced in the database, not in workflows** — postings
  summing to zero above all — because there is more than one writer: n8n, the
  statement importer, and corrections from the app (ADR 0007).
- **Merchants are a first-class table, not a text column**, with an alias table
  mapping raw observed strings — typed phrases and bank statement descriptors —
  onto one merchant. Recognition is a lookup against aliases first; only an
  unmatched string is escalated to the model, and the result is written back as
  a new merchant or a new alias. The registry therefore grows by use.
- **Category defaults live on the merchant**, so classification improves as the
  registry fills, and the model is consulted less over time rather than more.
- **Money is stored as integer minor units with an explicit currency**, never as
  a float. Default currency EUR.
- **Reporting is SQL**, not workflow logic. Aggregation lives in views, so the
  agent asks the database rather than computing in n8n.

Backups are of this database specifically, and restoring it is tested as part of
the home-server migration slice.

## Alternatives

| Option | Why rejected |
|---|---|
| Google Sheets / Airtable as the ledger | Convenient and viewable, but the ledger would live outside the household and outside our control — against the privacy and portability principles. Also no real constraints, so data quality decays |
| Baserow or NocoDB as the primary store | Attractive for a spreadsheet-like view over the ledger, but then the schema is owned by a tool. Either may still be added later *as a read-only view* over this PostgreSQL, which is a separate decision |
| SQLite | Fine at this data volume, but PostgreSQL is already running for n8n, so SQLite adds a second storage technology for nothing |
| n8n's own internal database, alongside its tables | Couples our ledger's lifetime to the platform's schema and upgrade path. The ledger must survive replacing n8n |
| A free-text merchant column, no registry | Makes automatic recognition impossible and leaves the model re-guessing the same merchant forever, at cost, with inconsistent spellings in every report |

## Consequences

**Good:**
- The asset survives any platform change: workflows are rewritten, the ledger is
  carried over.
- Real constraints, real types, real transactions — the data can be trusted.
- Reporting is a SQL problem, which is a solved problem.
- Merchant recognition gets cheaper and more accurate with use, instead of
  costing an LLM call per expense forever.

**Bad, and the price we accept:**
- Writing SQL and migrations is code, in a project that chose low-code. This is
  the deliberate exception: the schema is exactly where code pays for itself.
- No spreadsheet view out of the box; until a view tool is added, inspecting the
  ledger outside the bot means SQL.
- An auto-growing merchant registry will accumulate duplicates and junk; merging
  merchants has to be a supported operation, not a manual database chore.

**What becomes harder to change later:**
- The schema. Renaming or restructuring core tables once years of entries exist
  is real work, which is why migrations are versioned and reviewed from the first
  commit.
