---
id: 0031
title: The chart of accounts is editable data — by an admin, and by the agent on an admin's instruction
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amends: [0011, 0017]
---

# ADR 0031 — The chart of accounts is editable data: by an admin, and by the agent on an admin's instruction

## Context

ADR 0011 established double-entry with a chart of accounts and said the chart is
owned by us and versioned in migrations. That is right for the *structure* and
wrong for the *contents*: a household opens an account, closes a card, or decides
that "Transport" should be split — and none of those should require a developer, a
migration and a deployment.

Categories are the same shape with an extra wrinkle. Deciding a taxonomy up front
is an argument nobody wins on day one, and an unbounded free-for-all produces
three spellings of "groceries". What the household wants is for the system to
propose and for an admin to curate.

This ADR **amends two clauses** and leaves the rest of both decisions intact:
ADR 0011's statement that the chart lives in migrations, and ADR 0017's
assumption that domain slugs are fixed by us. Everything else in 0011 — the
postings invariant, the account types, sign conventions, cash-basis recognition —
and in 0017 — slugs with translations, merchant names as data — stands unchanged.

## Decision

**Account types and invariants are code. Accounts and categories are data.**

### What stays in migrations

- The five account **types** — asset, liability, income, expense, equity — and
  their sign conventions.
- The postings-sum-to-zero invariant, the triggers, the audit log, the views.
- The reserved accounts the system itself depends on, such as opening balances.

An admin cannot invent an account type, break the invariant, or delete a reserved
account. Those are the guarantees the books rest on.

### Who may write it

Two writers, and the distinction matters more than the list:

- **An admin, by hand**, in the app.
- **The agent, in chat, on an admin's instruction.** "Open a savings account at
  Bunq" or "split Transport into Fuel and Public transport" is an admin action
  expressed conversationally — the agent executes it **as the admin who asked**,
  so authorisation is the admin's role and row-level security needs no exception
  (ADRs 0014, 0016). The agent has no authority of its own over structure.

Two rules keep that honest:

- **Structural changes are confirmed before they are applied.** The agent restates
  what it is about to create, rename or merge, and waits. A transaction can be
  corrected cheaply; a merged category affects every past report.
- **The acting admin is recorded, not the agent.** The audit row says who asked
  (ADR 0008); that the agent carried it out is provenance, not authorship.

The one thing the agent does create **unprompted** is a category it met and could
not place — and that path is flagged unreviewed, below.

### What is managed as data

- **Accounts**: create, rename, set and change terms (limits, rates, effective
  dates per ADR 0008), deactivate. **Never delete** where postings exist —
  deactivation hides an account from pickers and keeps its history.
- **Categories**: rename, re-parent, merge, deactivate, and edit the display name
  in each language.
- **Merchant-to-category defaults**, which already worked this way (ADR 0004).

### Categories are learned, then curated

- **The agent creates a category when it meets one it cannot place**, deriving a
  slug and a provisional display name in both languages (ADR 0017). This is the
  only structural write it makes without being asked, and it is confined to
  categories: it never creates an account on its own.
- **New categories are flagged as unreviewed** until an admin has looked at them,
  so a taxonomy assembled by a model is visible as such.
- **Merging is first-class**, because a learned taxonomy accumulates near
  duplicates — the same mechanism the merchant registry already needs (ADR 0004).
- **A category's slug is stable once created**; renaming changes display names, so
  reports remain comparable across a rename.

### What this costs, and how it is contained

Configurable data that reports depend on is a foot-gun, so:

- Every change is audited like any other (ADR 0008), including renames and merges.
- A merge is a single reversible operation, not a bulk re-categorisation.
- **Reports group by slug**, so no report breaks when a name changes.
- Only an admin may do any of it (ADR 0016), and the row-level security tests
  cover that (ADR 0015).
- The seeded synthetic household ships a **starter chart and a starter category
  set**, so nobody faces an empty taxonomy on day one — and neither is a
  migration anybody has to edit.

## Alternatives

| Option | Why rejected |
|---|---|
| Chart and categories only in migrations | ADR 0011's original clause. Correct for invariants, wrong for contents: opening a bank account would be a code change and a deploy |
| A fixed category list decided up front | Comparable reports from day one, and it demands a taxonomy argument before anyone has data to argue from, then ossifies the loser |
| Unbounded free-text categories | Three spellings of one category, no comparability, and no report worth reading |
| Learned categories with no curation | What the model proposes accumulates duplicates and oddities; without merging and review it decays within months |
| Let members manage the chart too | Category and project attribution are classification and are open to members (ADR 0021), but creating accounts is a structural act. It belongs with the people who own the books |
| Let the agent restructure on its own judgement | Attractive — it sees the data — and it would let a model reorganise the household's reporting history unasked. Proposing is welcome; deciding is not |
| Require every structural change to go through the app | Safer, and it would mean leaving a conversation to do something the conversation just established. The confirmation step is the safety, not the surface |

## Consequences

**Good:**
- Opening an account or fixing a taxonomy is a minute in the app, not a release.
- No taxonomy has to be invented before there is data, and what the system learns
  is visible as unreviewed until someone agrees with it.
- Slug-stable reporting means a rename is free and comparability survives it.

**Bad, and the price we accept:**
- The chart is no longer reproducible from the repository alone: a rebuild needs
  the database, which the backups already guarantee (ADR 0009) but the
  configuration-as-code principle no longer covers. This is a real narrowing of
  ADR 0010's claim, and it is the price of not shipping a migration to open a
  savings account.
- A learned taxonomy will produce near-duplicates, and merging them is a recurring
  small chore — named in the chore table in `docs/standards/ergonomics.md`.
- More admin surface in the app means more ways to be confused by one's own data.
- A conversational path to structural change is powerful and a model is imprecise:
  the confirmation step is the only thing between "split Transport" and a merge
  nobody wanted. It has to be real, not a formality.

**What becomes harder to change later:** moving back to a migration-only chart
would mean importing whatever the household has built up. Slug stability and the
audit log are what keep that possible rather than painful.
