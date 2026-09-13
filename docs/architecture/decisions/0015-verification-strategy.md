---
id: 0015
title: Verification strategy — tests against a real database, ranked by what it costs to be wrong
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0015 — Verification strategy: tests against a real database, ranked by what it costs to be wrong

## Context

The process in this repository requires a spec's acceptance criteria to be
closed with evidence (`/spec-review`), but nothing yet says what counts as
evidence. Without that, "verified" degrades into "I looked at it", which is
exactly the failure the spec-driven process exists to prevent.

Three properties of this system decide what the strategy has to be:

- **The logic is in the database.** The double-entry invariant is a constraint,
  the audit log is a trigger, the reports are views, and after ADR 0014 the
  *authorisation* is row-level security. Tests that mock the database would test
  nothing that matters.
- **There is more than one writer.** n8n, the statement importer and corrections
  from the app all write. A rule enforced in one caller is not enforced.
- **Part of the system is non-deterministic.** A model extracts expenses from
  free text and reads PDFs. That cannot be unit-tested, and pretending otherwise
  produces flaky tests that get disabled.

The household is three people and the project is built by one owner and an agent,
so the strategy also has to be proportionate: effort goes where being wrong is
expensive, and nowhere else.

## Decision

The properties these tests exist to prove are listed in
[docs/standards/threat-model.md](../../standards/threat-model.md); without it, a
policy test only asserts whatever the policy happens to say.

### The ranking that drives everything

Test effort is allocated by what it costs to be wrong, not evenly:

| Rank | What | Cost of being wrong |
|---|---|---|
| 1 | Row-level security policies | A leak between household members — silent, and about money |
| 2 | The double-entry invariant and the audit triggers | Books that do not balance, or changes with no trace |
| 3 | Statement parsing and reconciliation | Wrong financial truth, applied in bulk |
| 4 | View contracts | Silently broken app or digest |
| 5 | Migrations | An unrecoverable schema |
| 6 | Capture workflows end to end | A lost or wrong expense, noticed and fixable |
| 7 | The app's screens | An ugly or confusing page, noticed immediately |
| 8 | Model extraction quality | Wrong guesses, which the design already treats as normal and correctable |

### Tests run against a real PostgreSQL. Always.

Every database test runs against a throwaway PostgreSQL container with the real
migrations applied. **Nothing about the database is mocked**, because the
invariants under test *are* the database.

- **pgTAP** is the test framework for everything in the database: constraints,
  triggers, functions, views and policies.
- **Row-level security is tested by impersonation**, not by inspection. A test
  sets `request.jwt.claims` the way PostgREST does and asserts what that member
  can and cannot see or write — including the negative cases, which are the point:
  one member must not reach another's rows where the policy says so, the
  household role must not be able to insert a raw posting, and an unauthenticated
  request must see nothing at all.
- **The invariant is tested by attacking it directly**: attempts to write
  unbalanced postings, to modify an audit row, to delete a transaction without a
  trace — each asserted to fail at the database, not at the caller.

### View contracts are snapshotted

The app and the digests bind to views (ADRs 0007, 0014), so a view's column names
and types are a public interface. A test asserts each view's signature against a
committed snapshot: a migration that changes one fails the test and has to
acknowledge the change, instead of silently breaking a screen.

### Parsers are pure functions over committed fixtures

Statement parsing (ADR 0013) is tested as pure transformation: real sample files
— **anonymised**, with amounts and names replaced — committed as fixtures, and
asserted to produce the expected normalised statement lines and to reconcile to
the stated closing balance. Reconciliation is tested on top of a seeded ledger,
including the cases that matter: a duplicate already captured by hand, a card
settlement that must become a transfer, and a PDF-derived line superseded by a
later structured import.

**No real household statement, receipt or balance is ever committed to this
repository.**

### Workflows are tested end to end, with the model stubbed

n8n workflow nodes are kept thin by design, with logic in SQL. What is tested is
therefore the whole path, not the nodes:

- A workflow runs headless (`n8n execute`) against a seeded throwaway database
  with a fixture Telegram update as input, and the assertion is **the resulting
  ledger state** — which transaction, which postings, which provenance — not the
  node's internals.
- **The model gateway is stubbed** by pointing the base URL at a local mock that
  replays recorded responses. Tests are then deterministic, free and offline, and
  the failure paths — a timeout, a refusal, an unbalanced suggestion — become
  ordinary test cases rather than things we hope work.

### Model quality is a graded harness, not a test

Prompt behaviour is measured, never asserted:

- A **golden set** of real-shaped captures — Dutch comma decimals, "on the credit
  card", a stated past date, two amounts in one message, deliberate nonsense —
  each with the expected extraction.
- It runs **on demand**, before a prompt or model change, and reports a score
  rather than passing or failing a build. Numbers and account choices are scored
  strictly; wording is not scored at all.
- It never runs in continuous integration: it costs money and it is not
  deterministic.

### The app gets a few journeys, not coverage

The app is thin by design, so: **Vitest** for anything with logic worth naming,
and **Playwright** for a small set of journeys at phone viewport against a seeded
database — open the app, see the balances, open a category, correct a
transaction. Screenshot and visual-regression tests are deliberately **excluded**:
appearance is edited by hand through Onlook (ADR 0007), and pinning it would make
an admin's own tool fight the test suite.

### Seed data is a first-class artefact

A committed seed script builds a synthetic household: three members, the real
account *shapes* (two current accounts, cash, a credit card, a loan with an
overdraft limit somewhere), and several months of transactions including a card
settlement, cash-advance fees, overdraft interest and a loan payment split. It
serves the tests, the app's development, and the reports — and it exercises the
awkward cases every time anyone looks at a screen.

### Where it runs, and what gates what

- **Locally**, through the task runner, as one command.
- **In GitHub Actions on every push**: migrations from scratch, pgTAP, view
  snapshots, parser tests, Vitest, and the app's Playwright journeys.
- **On demand**: the n8n end-to-end workflows, which need the container, and the
  golden set, which costs money (ADR 0025 gates prompt changes on it).
- **Monthly**: the restore verification from ADR 0009 — which is a test, and the
  only one whose subject is the backups.

**What counts as evidence in a spec review is a named, passing test** — file and
test name — or, where a criterion genuinely cannot be automated (a passkey on a
physical iPhone, the migration to the home server), a recorded manual run with
its date. Prose is not evidence.

## Alternatives

| Option | Why rejected |
|---|---|
| Mock the database, unit-test the callers | Would verify the one layer that holds none of the rules. A passing suite would say nothing about whether the books balance or whether a member can read another's rows |
| Application-level integration tests only, no pgTAP | Tests policies only through the paths the app happens to use, and leaves the other writers — workflows, the importer, psql — untested. The rules are in the database, so the tests belong there |
| Assert on model output in continuous integration | Non-deterministic and paid. It produces flaky builds, which get disabled, which leaves no measurement at all. Grading on demand keeps the measurement and drops the flakiness |
| Test n8n nodes in isolation | There is nothing meaningful inside a thin node. The interesting behaviour is the path from a Telegram update to a balanced transaction |
| Visual regression on the app | Would fight Onlook, which exists precisely so appearance can change freely |
| Full coverage targets | A number that would be met by testing the easy half. The ranking above is the substitute, and it is deliberately uneven |
| Trust the process — specs, review, careful work | This *is* the process. The spec-driven method promises evidence per criterion; without tests there is nothing to point at |

## Consequences

**Good:**
- The highest-risk thing in the system — a policy that leaks money data between
  family members — is the most tested, and tested by impersonation rather than by
  reading policy text.
- Every writer is covered at once, because the rules are tested where they are
  enforced.
- Capture workflows are testable offline and for free, which means the failure
  paths get tested instead of assumed.
- Spec reviews get to cite a test name, which is what makes the process honest.
- The seed household makes the awkward accounting cases visible constantly, not
  only when a bug is reported.

**Bad, and the price we accept:**
- pgTAP is an unfamiliar tool and SQL tests are verbose. The alternative is worse.
- Anonymising real statement files to make fixtures is manual work, and it must be
  done carefully every time a new format appears.
- The recorded model responses will drift from what the live model returns, so
  the golden set has to be run deliberately or the stubs quietly become fiction.
- Continuous integration needs a PostgreSQL service and the migrations to be
  fast; if either rots, the suite stops being run.
- Model quality is graded rather than gated, so a prompt regression can reach the
  household. Accepted, because the design already treats wrong extraction as a
  normal, cheaply correctable event.

**What becomes harder to change later:**
- The view snapshots become a mild brake on refactoring views — which is the
  intended effect, since the app depends on them. Versioning a view rather than
  mutating it is the escape.
