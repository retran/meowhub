---
id: 0015
title: Verification strategy — tests against a real database, ranked by what it costs to be wrong
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0015 - Verification strategy: tests against a real database, ranked by what it costs to be wrong

## Context

The process in this repository requires a spec's acceptance criteria to be
closed with evidence (`/spec-review`), but nothing yet says what counts as
evidence. Until we say, "verified" decays into "I looked at it", which is the
failure the spec-driven process exists to prevent.

Three properties of this system decide what the strategy has to be:

- The logic is in the database. The double-entry invariant is a constraint, the
  audit log is a trigger, the reports are views, and after ADR 0014 the
  authorisation is row-level security, so a test that mocks the database would
  test nothing that matters.
- More than one writer exists. n8n, the statement importer and corrections from
  the app all write, so a rule we enforce in one caller isn't enforced at all.
- Part of the system is non-deterministic. A model extracts expenses from free
  text and reads PDFs, which we can't unit-test; pretending we can produces
  flaky tests that somebody then disables.

The household is three people and the project is built by one owner and an
agent, so the strategy also has to be proportionate: we spend effort where being
wrong is expensive, and nowhere else.

## Decision

The properties these tests exist to prove are listed in
[docs/standards/threat-model.md](../../standards/threat-model.md). Without that
document, a policy test only asserts whatever the policy happens to say.

### The ranking that drives everything

We allocate test effort by what it costs to be wrong, not evenly:

| Rank | What | Cost of being wrong |
|---|---|---|
| 1 | Row-level security policies | A leak between household members - silent, and about money |
| 2 | The double-entry invariant and the audit triggers | Books that do not balance, or changes with no trace |
| 3 | Statement parsing and reconciliation | Wrong financial truth, applied in bulk |
| 4 | View contracts | Silently broken app or digest |
| 5 | Migrations | An unrecoverable schema |
| 6 | Capture workflows end to end | A lost or wrong expense, noticed and fixable |
| 7 | The app's screens | An ugly or confusing page, noticed immediately |
| 8 | Model extraction quality | Wrong guesses, which the design already treats as normal and correctable |

### Tests run against a real PostgreSQL. Always.

Every database test runs against a throwaway PostgreSQL container with the real
migrations applied. We mock nothing about the database, because the invariants
under test are the database.

- **pgTAP** is the test framework for everything in the database: constraints,
  triggers, functions, views and policies.
- We test row-level security by impersonation rather than by reading policy
  text. A test sets `request.jwt.claims` the way PostgREST does and asserts what
  that member can and cannot see or write. The negative cases are the point: one
  member must not reach another's rows where the policy says so, the household
  role must not be able to insert a raw posting, and an unauthenticated request
  must see nothing at all.
- We test the invariant by attacking it directly, with attempts to write
  unbalanced postings, to modify an audit row and to delete a transaction
  without a trace, each asserted to fail at the database and not at the caller.

### View contracts are snapshotted

The app and the digests bind to views (ADRs 0007, 0014), so a view's column
names and types are a public interface. A test asserts each view's signature
against a committed snapshot, so a migration that changes one fails the test and
has to acknowledge the change instead of silently breaking a screen.

### Parsers are pure functions over committed fixtures

We test statement parsing (ADR 0013) as a pure transformation. Real sample
files, anonymised with amounts and names replaced, are committed as fixtures,
and we assert that they produce the expected normalised statement lines and
reconcile to the stated closing balance. Reconciliation is tested on top of a
seeded ledger, including the cases that matter: a duplicate already captured by
hand, a card settlement that must become a transfer, and a PDF-derived line
superseded by a later structured import.

**No real household statement, receipt or balance is ever committed to this
repository.**

### Workflows are tested end to end, with the model stubbed

We keep n8n workflow nodes thin by design and put the logic in SQL, so what we
test is the whole path rather than the nodes:

- A workflow runs headless (`n8n execute`) against a seeded throwaway database
  with a fixture Telegram update as input, and the test asserts the resulting
  ledger state - which transaction, which postings, which provenance - and never
  the node's internals.
- We stub the model gateway by pointing the base URL at a local mock that
  replays recorded responses. The tests are then deterministic, free and
  offline, and the failure paths - a timeout, a refusal, an unbalanced
  suggestion - become ordinary test cases we can write instead of behaviour we
  hope works.

### Model quality is a graded harness, not a test

We measure prompt behaviour and never assert on it:

- A golden set holds real-shaped captures - Dutch comma decimals, "on the credit
  card", a stated past date, two amounts in one message, deliberate nonsense -
  each with the expected extraction.
- It runs on demand, before a prompt or model change, and reports a score
  instead of passing or failing a build. We score numbers and account choices
  strictly and don't score wording at all.
- It never runs in continuous integration, because it costs money and it isn't
  deterministic.

### The app gets a few journeys, not coverage

The app is thin by design, so we use **Vitest** for anything with logic worth
naming and **Playwright** for a small set of journeys at phone viewport against
a seeded database: open the app, see the balances, open a category, correct a
transaction. We deliberately exclude screenshot and visual-regression tests,
because an admin edits appearance by hand through Onlook (ADR 0007) and pinning
it would make that tool fight the test suite.

### Seed data is a first-class artefact

A committed seed script builds a synthetic household: three members, the real
account shapes (two current accounts, cash, a credit card, a loan with an
overdraft limit somewhere), and several months of transactions including a card
settlement, cash-advance fees, overdraft interest and a loan payment split. The
same script serves the tests, the app's development and the reports, so it puts
the awkward cases in front of anyone who opens a screen.

### Where it runs, and what gates what

- Locally, through the task runner, as one command.
- In GitHub Actions on every push: migrations from scratch, pgTAP, view
  snapshots, parser tests, Vitest, and the app's Playwright journeys.
- On demand: the n8n end-to-end workflows, which need the container, and the
  golden set, which costs money (ADR 0025 gates prompt changes on it).
- Monthly: the restore verification from ADR 0009, which is a test, and the only
  one whose subject is the backups.

A spec review closes a criterion by citing a named, passing test, with its file
and test name. Where a criterion genuinely can't be automated, such as a passkey
on a physical iPhone or the migration to the home server, a recorded manual run
with its date closes it instead. Prose is not evidence.

## Alternatives

| Option | Why rejected |
|---|---|
| Mock the database, unit-test the callers | Would verify the one layer that holds none of the rules. A passing suite would say nothing about whether the books balance or whether a member can read another's rows |
| Application-level integration tests only, no pgTAP | Tests policies only through the paths the app happens to use, and leaves the other writers - workflows, the importer, psql - untested. The rules are in the database, so the tests belong there |
| Assert on model output in continuous integration | Non-deterministic and paid, so it produces flaky builds, which get disabled, which leaves no measurement at all. Grading on demand keeps the measurement and drops the flakiness |
| Test n8n nodes in isolation | A thin node holds nothing meaningful. The interesting behaviour is the path from a Telegram update to a balanced transaction |
| Visual regression on the app | Would fight Onlook, which exists so that appearance can change freely |
| Full coverage targets | A number we would meet by testing the easy half. The ranking above replaces it, and it is deliberately uneven |
| Trust the process - specs, review, careful work | The process is what asks for this ADR: the spec-driven method promises evidence per criterion, and without tests there is nothing to point at |

## Consequences

**Good:**
- The highest-risk thing in the system, a policy that leaks money data between
  family members, is the most tested, and we test it by impersonation rather
  than by reading policy text.
- Every writer is covered at once, because we test the rules where the database
  enforces them.
- Capture workflows are testable offline and for free, so we test the failure
  paths instead of assuming them.
- A spec review can cite a test name, which is what keeps the process honest.
- The seed household keeps the awkward accounting cases visible all the time,
  and not only when somebody reports a bug.

**Bad, and the price we accept:**
- pgTAP is an unfamiliar tool and SQL tests are verbose, and we take that cost
  because testing the rules anywhere else would miss them.
- Anonymising real statement files to make fixtures is manual work, and we have
  to redo it carefully every time a new format appears.
- The recorded model responses will drift from what the live model returns, so
  we have to run the golden set deliberately or the stubs quietly turn into
  fiction.
- Continuous integration needs a PostgreSQL service and fast migrations, and if
  either rots, people stop running the suite.
- We grade model quality instead of gating on it, so a prompt regression can
  reach the household. We accept that, because the design already treats wrong
  extraction as a normal event that costs little to correct.

**What becomes harder to change later:**
- The view snapshots put a mild brake on refactoring views, which is the effect
  we want, since the app depends on them. When we need a breaking change, we
  version the view instead of mutating it.
