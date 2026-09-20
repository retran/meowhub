---
id: 0004
title: PostgreSQL as the system of record
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0004 - PostgreSQL as the system of record

## Context

The ledger is the one asset in this project we cannot replace, because we can
rewrite workflows and prompts and even swap the platform, and we cannot recreate
years of household expenses. Where that data lives, and in what shape, outlives
every other decision here.

n8n already needs PostgreSQL for its own state (ADR 0001), so a database runs
either way, and the open question is whether the ledger lives in it under a
schema we own or somewhere else.

The system also has to recognize merchants by itself and learn new ones. A
statement line reading `ALBERT HEIJN 1234 AMSTERDAM` and a typed "albert heijn"
must land on the same merchant, and a merchant nobody has seen before must
become a known one without the owner editing anything by hand.

## Decision

**PostgreSQL is the system of record.** It holds the ledger, the household
members, the merchant registry, the message log and imported statements, in a
schema we design and migrate deliberately, in its own database and separate from
the one n8n uses for its internal state.

We decide the *shape* of the ledger separately, in ADR 0011: it is double-entry,
with a chart of accounts. This ADR says where the data lives and who owns the
schema, ADR 0011 says what the rows mean, and ADR 0012 keeps budgets,
commitments and plans in their own tables, out of the ledger.

We own the schema rather than letting a tool infer it, which gives eight rules:

- Migrations are versioned SQL files in this repository, applied in order, and
  nobody changes the schema by clicking in a UI.
- The ledger keeps its history, so a correction writes a new state instead of
  silently overwriting the old one, because a member will correct an
  AI-guessed transaction often (vision principle 8).
- Every transaction records where it came from: which member submitted it, in
  which form (text, photo, voice, statement), and which model parsed it, if any.
- The database enforces the invariants, postings summing to zero above all,
  because three writers touch the ledger: n8n, the statement importer, and
  corrections from the app (ADR 0007).
- Merchants get their own table instead of a text column, with an alias table
  that maps raw observed strings onto one merchant, both typed phrases and bank
  statement descriptors. We look a string up against the aliases first and send
  only an unmatched string to the model, then write the answer back as a new
  merchant or a new alias, so the registry grows as the household uses it.
- Category defaults live on the merchant, so categorizing gets better as the
  registry fills and we call the model less over time.
- Money is stored as integer minor units with an explicit currency and never as
  a float. The default currency is EUR.
- Reporting is SQL and not workflow logic, so aggregation lives in views and the
  agent asks the database instead of computing in n8n.

We back up this database specifically, and we test restoring it as part of the
home-server migration slice.

## Alternatives

| Option | Why rejected |
|---|---|
| Google Sheets / Airtable as the ledger | Convenient and easy to look at, but the ledger would live outside the household and outside our control, against the privacy and portability principles. They also enforce no real constraints, so data quality decays |
| Baserow or NocoDB as the primary store | Attractive for a spreadsheet-like view over the ledger, but then a tool owns the schema. We can still add either later *as a read-only view* over this PostgreSQL, which is a separate decision |
| SQLite | Fine at this data volume, but PostgreSQL already runs for n8n, so SQLite would add a second storage technology and buy nothing |
| n8n's own internal database, alongside its tables | Ties the ledger's lifetime to the platform's schema and upgrade path, and the ledger has to survive replacing n8n |
| A free-text merchant column, no registry | Makes automatic recognition impossible and leaves the model re-guessing the same merchant forever, at cost, with inconsistent spellings in every report |

## Consequences

We gain four things:

- The asset survives any platform change, because we rewrite the workflows and
  carry the ledger over.
- Real constraints, real types and real transactions let us trust the data.
- Reporting becomes a SQL problem, which is a solved problem.
- Recognizing a merchant gets cheaper and more accurate as the household uses
  the system, instead of costing an LLM call per expense forever.

We accept three costs in return:

- SQL and migrations are code, in a project that chose low-code. We make the
  exception deliberately, because the schema is exactly where code pays for
  itself.
- No spreadsheet view comes out of the box, so until we add a view tool,
  inspecting the ledger outside the bot means writing SQL.
- A registry that grows by itself collects duplicates and junk, so merging two
  merchants has to be an operation the system supports and not a manual database
  chore.

The schema is what gets harder to change later. Renaming or restructuring a core
table once years of entries exist is real work, which is why we version and
review migrations from the first commit.
