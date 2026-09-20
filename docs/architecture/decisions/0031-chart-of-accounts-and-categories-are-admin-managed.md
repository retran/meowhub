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

# ADR 0031 - The chart of accounts is editable data: by an admin, and by the agent on an admin's instruction

## Context

ADR 0011 set up double-entry with a chart of accounts and said we own the chart
and version it in migrations. That holds for the structure and fails for the
contents, because a household opens an account, closes a card, or decides to
split "Transport", and none of those should need a developer, a migration, and a
deployment.

Categories have the same shape with one extra wrinkle. Nobody wins the argument
about a taxonomy on day one, and letting everyone type freely produces three
spellings of "groceries", so the household wants the system to propose and an
admin to curate.

This ADR amends two clauses and leaves the rest of both decisions intact: ADR
0011's statement that the chart lives in migrations, and ADR 0017's assumption
that we fix the domain slugs. Everything else in 0011 - the postings invariant,
the account types, sign conventions, cash-basis recognition - and in 0017 - slugs
with translations, merchant names as data - stands unchanged.

## Decision

Account types and invariants stay code, and accounts and categories become data.
The sections below say what stays in migrations, who can write the data, what
counts as data, how categories get learned and curated, and what containment we
put around the whole thing.

### What stays in migrations

Migrations keep the five account types - asset, liability, income, expense,
equity - and their sign conventions, the postings-sum-to-zero invariant with its
triggers, the audit log, the views, and the reserved accounts the system itself
depends on, such as opening balances.

An admin can't invent an account type, break the invariant, or delete a reserved
account, because those are the guarantees the books rest on.

### Who may write it

Two writers can change this data, and the difference between them matters more
than the list. An admin edits it by hand in the app. The agent edits it in chat
on an admin's instruction: "Open a savings account at Bunq" or "split Transport
into Fuel and Public transport" is an admin action expressed conversationally,
and the agent carries it out as the admin who asked, so the admin's role supplies
the authorisation and row-level security needs no exception (ADRs 0014, 0016).
The agent holds no authority of its own over structure.

Two rules keep that honest. The agent confirms a structural change before
applying it: it restates what it's about to create, rename, or merge, and waits,
because correcting a transaction is cheap while a merged category affects every
past report. And the audit row records the acting admin rather than the agent
(ADR 0008), since the agent carrying out the instruction is provenance rather
than authorship.

The one structural write the agent makes unprompted is a category it met and
couldn't place, and the section below flags that path as unreviewed.

### What is managed as data

Three kinds of data move out of migrations.

Accounts can be created, renamed, deactivated, and given terms that change over
time (limits, rates, effective dates per ADR 0008). We never delete an account
that has postings, because deactivating it hides it from pickers and keeps its
history. Categories can be renamed, re-parented, merged, deactivated, and given a
display name in each language. Merchant-to-category defaults already worked this
way (ADR 0004).

### Categories are learned, then curated

When the agent meets a category it can't place, it creates one, deriving a slug
and a provisional display name in both languages (ADR 0017). That's the only
structural write it makes without being asked, and it covers categories only: the
agent never creates an account on its own.

We flag a new category as unreviewed until an admin has looked at it, so anyone
reading the taxonomy can see which parts a model assembled. Merging is a
first-class operation, because a learned taxonomy accumulates near-duplicates -
the same problem the merchant registry already has (ADR 0004). A category's slug
stays fixed once created, so a rename changes only display names and reports stay
comparable across it.

### What this costs, and how it is contained

Configurable data that reports depend on is a foot-gun, so we contain it in five
ways.

We audit every change like any other (ADR 0008), including renames and merges,
and we make a merge a single reversible operation instead of a bulk
re-categorisation. Reports group by slug, so a name change breaks no report. Only
an admin can do any of it (ADR 0016), and the row-level security tests cover that
(ADR 0015). The seeded synthetic household ships a starter chart and a starter
category set, so nobody faces an empty taxonomy on day one and nobody has to edit
a migration to get one.

## Alternatives

| Option | Why rejected |
|---|---|
| Chart and categories only in migrations | ADR 0011's original clause. Correct for invariants, wrong for contents: opening a bank account would be a code change and a deploy |
| A fixed category list decided up front | Comparable reports from day one, and it demands a taxonomy argument before anyone has data to argue from, then ossifies the loser |
| Unbounded free-text categories | Three spellings of one category, no comparability, and no report worth reading |
| Learned categories with no curation | What the model proposes accumulates duplicates and oddities; without merging and review it decays within months |
| Let members manage the chart too | Category and project attribution are classification and are open to members (ADR 0021), but creating accounts is a structural act. It belongs with the people who own the books |
| Let the agent restructure on its own judgement | Attractive - it sees the data - and it would let a model reorganise the household's reporting history unasked. Proposing is welcome; deciding is not |
| Require every structural change to go through the app | Safer, and it would mean leaving a conversation to do something the conversation just established. The confirmation step is the safety, not the surface |

## Consequences

Good:
- Opening an account or fixing a taxonomy takes a minute in the app instead of a
  release.
- Nobody has to invent a taxonomy before there's data, and what the system learns
  stays marked unreviewed until someone agrees with it.
- Reporting groups by slug, so a rename costs nothing and comparability survives
  it.

Bad, and the price we accept:
- The repository alone no longer reproduces the chart: a rebuild needs the
  database, which the backups guarantee (ADR 0009) but the configuration-as-code
  principle no longer covers. That genuinely narrows ADR 0010's claim, and it's
  what we pay for not shipping a migration to open a savings account.
- A learned taxonomy produces near-duplicates, so merging them becomes a
  recurring small chore, named in the chore table in
  `docs/standards/ergonomics.md`.
- More admin surface in the app gives everyone more ways to confuse themselves
  with their own data.
- A conversational path to structural change is powerful and a model is
  imprecise, so the confirmation step is the only thing standing between "split
  Transport" and a merge nobody wanted. It has to be real rather than a
  formality.

What becomes harder to change later is going back to a migration-only chart,
which would mean importing whatever the household has built up. Slug stability
and the audit log are what keep that possible instead of painful.
