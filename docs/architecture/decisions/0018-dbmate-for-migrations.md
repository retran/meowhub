---
id: 0018
title: dbmate for schema migrations, with the dumped schema as a reviewed artefact
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0018 — dbmate for schema migrations, with the dumped schema as a reviewed artefact

## Context

Everything load-bearing in this system is in the database: the double-entry
invariant, the audit triggers, the reporting views, and the row-level security
policies that ADR 0014 made the authorisation mechanism. ADRs 0004 and 0010
require that the schema change only through versioned migrations in this
repository. Nothing yet says with what.

The choice matters less for features than for what it demands: this project is one
owner and an agent, on a small VPS, and the tool must not become a subject of
study.

## Decision

**dbmate.** A single Go binary, migrations as plain SQL files with `-- migrate up`
and `-- migrate down`, applied in filename order, recorded in a
`schema_migrations` table, configured by a database URL from the environment.

- **Plain SQL, no DSL and no ORM.** The migrations contain the constraints,
  triggers, views, functions and policies verbatim, which is also what makes them
  reviewable.
- **`schema.sql` is dumped on every migration and committed.** This doubles as the
  schema snapshot ADR 0015 wants: a migration that changes a view's signature or a
  policy shows up as a reviewable diff in one file, instead of being buried in a
  new migration nobody reads twice.
- **Forward-only in practice.** Down migrations are written because they are cheap
  and useful locally, but recovery in production is a restore (ADR 0009), not a
  rollback.
- **Migrations run as a container in the Compose file**, before the dependent
  services, so bootstrap and rebuild are one command (spec 0001).
- **No ad-hoc DDL, ever** — including "just one column". Drift detection
  (ADR 0010) treats a schema that does not match the dump as drift.

## Alternatives

| Option | Why rejected |
|---|---|
| Plain SQL files with a hand-written runner | Tempting at this size, and the ordering, tracking and idempotency are exactly the boring parts that go wrong. dbmate is that runner, already correct |
| Sqitch | More powerful: dependency graphs rather than ordering, proper verify scripts. Heavier to learn and a Perl toolchain to keep on the host, for a benefit this schema is too small to need |
| Atlas | Declarative diffing is genuinely attractive for a schema with many views, and it is the strongest alternative. Rejected for now because generated-diff migrations are harder to review than hand-written SQL, and reviewability is the whole point here. Worth revisiting if view churn becomes painful |
| Flyway or Liquibase | JVM, and XML in Liquibase's case. Wrong shape for a 2 GB host and a plain-SQL schema |
| golang-migrate | Very close to dbmate in spirit; dbmate is chosen for the schema dump and the simpler single-file migration format |
| An ORM's migration generator | There is no application framework owning this schema, and there should not be: the database is the system of record, not a projection of some code's models |

## Consequences

**Good:**
- Migrations are readable SQL, which is what a reviewer of a financial invariant
  needs to see.
- The committed `schema.sql` gives a single diff for "what actually changed",
  serving review, ADR 0015's snapshots and onboarding at once.
- One static binary; nothing to install on the host beyond a container.

**Bad, and the price we accept:**
- No dependency resolution: ordering is by filename, so two parallel branches
  touching the schema will conflict and must be resolved by hand. At one
  contributor and an agent, this is theoretical.
- No verify step of its own — correctness of a migration is proven by the pgTAP
  suite (ADR 0015), not by the migration tool.
- Writing triggers and policies by hand is more verbose than a declarative tool
  would be.

**What becomes harder to change later:** very little. Migrations are plain SQL, so
switching runners means adopting the same files under different bookkeeping.
