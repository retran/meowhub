---
id: 0018
title: dbmate for schema migrations, with the dumped schema as a reviewed artefact
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0018 - dbmate for schema migrations, with the dumped schema as a reviewed artefact

## Context

Everything load-bearing in this system lives in the database: the double-entry
invariant, the audit triggers, the reporting views, and the row-level security
policies that ADR 0014 made the way we authorise a request. ADRs 0004 and 0010
require the schema to change only through versioned migrations in this
repository, and nothing yet says which tool applies them.

The choice matters less for what a tool can do than for what it demands of us.
This project is one owner and an agent on a small VPS, so the tool must not
become a subject of study.

## Decision

We use **dbmate**: a single Go binary that applies migrations written as plain
SQL files with `-- migrate up` and `-- migrate down`, in filename order, records
them in a `schema_migrations` table, and takes its configuration from a database
URL in the environment.

- We write plain SQL, with no DSL and no ORM, so the migrations hold the
  constraints, triggers, views, functions and policies word for word, which is
  also what makes them reviewable.
- dbmate dumps `schema.sql` on every migration and we commit it. The dump
  doubles as the schema snapshot ADR 0015 asks for, so a migration that changes
  a view's signature or a policy shows up as a diff in one file instead of
  hiding in a new migration nobody reads twice.
- We are forward-only in practice. We write down migrations because they're
  cheap and useful locally, but we recover production by restoring a backup
  (ADR 0009) rather than by rolling back.
- Migrations run as a container in the Compose file, before the services that
  depend on them, so bootstrap and rebuild stay one command (spec 0001).
- We never run ad-hoc DDL, including "just one column", because drift detection
  (ADR 0010) treats a schema that doesn't match the dump as drift.

## Alternatives

| Option | Why rejected |
|---|---|
| Plain SQL files with a hand-written runner | Tempting at this size, but the ordering, tracking and idempotency are the boring parts that go wrong, and dbmate is that runner with those parts already correct |
| Sqitch | More powerful, with dependency graphs instead of ordering and proper verify scripts, but heavier to learn and a Perl toolchain to keep on the host, for a benefit this schema is too small to need |
| Atlas | Declarative diffing is genuinely attractive for a schema with many views, and this is the strongest alternative. We rejected it for now because a generated-diff migration is harder to review than hand-written SQL, and reviewability is the point. Worth revisiting if view churn becomes painful |
| Flyway or Liquibase | A JVM, and XML in Liquibase's case, which is the wrong shape for a 2 GB host and a plain-SQL schema |
| golang-migrate | Very close to dbmate in spirit. We picked dbmate for the schema dump and the simpler single-file migration format |
| An ORM's migration generator | No application framework owns this schema, and none should: the database is the system of record and not a projection of some code's models |

## Consequences

**Good:**
- Migrations are readable SQL, which is what a reviewer of a financial invariant
  has to see.
- The committed `schema.sql` gives one diff for what actually changed, which
  serves review, ADR 0015's snapshots and onboarding at once.
- One static binary, so there is nothing to install on the host beyond a
  container.

**Bad, and the price we accept:**
- dbmate resolves no dependencies and orders by filename, so two parallel
  branches that touch the schema conflict and somebody has to resolve them by
  hand. With one contributor and an agent, that stays theoretical.
- dbmate has no verify step, so the pgTAP suite (ADR 0015) proves a migration
  correct, not the migration tool.
- Writing triggers and policies by hand takes more lines than a declarative tool
  would.

**What becomes harder to change later:** very little, because the migrations are
plain SQL, so switching runners means adopting the same files under different
bookkeeping.
