---
id: 0012
title: Budgets, recurring commitments and planned purchases are forecast objects, never postings
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0012 — Budgets, recurring commitments and planned purchases are forecast objects, never postings

## Context

Running the household like a small firm means knowing not only what happened but
what is coming. Three requirements arrived together, and they are the same shape:

- **Budgeting** — how much this household intends to spend per category per month.
- **Mandatory recurring expenses** — rent or mortgage, utilities, insurance,
  subscriptions, the loan payment from ADR 0011. Known in advance, largely fixed,
  and the reason a month is tight or comfortable.
- **Planned purchases** — things the household intends to buy, each scheduled on
  a date. This is the planning module: a list of intentions with dates and
  amounts, which only becomes real when someone actually buys something.

All three are *expectations*. The ledger (ADR 0011) records *events*. The
temptation is to post expectations into the ledger as pending or forecast
transactions, so that one query answers everything. That makes balances and
reports lie: a planned sofa would reduce the bank balance before anyone bought a
sofa, and the trial balance would be asserting something untrue.

## Decision

**Only things that happened become postings.** Budgets, commitments and planned
purchases live in their own tables and never touch the ledger.

- **Budget:** an amount for a category (an expense account subtree) for a period,
  with an optional rollover of the unspent remainder into the next period.
  Compared against actual postings at read time, in SQL views.
- **Commitment:** a recurring obligation — amount or estimate, cadence, the
  account it is paid from, the category, and a next-due date. A commitment
  *expects* a transaction; it does not create one. The loan amortisation from
  ADR 0011 is a commitment whose expected split is computed rather than fixed.
- **Planned purchase:** a one-off intended spend with a target date, an estimated
  amount, a category and a priority. It has a lifecycle — `planned`,
  `done`, `dropped`, `postponed` — and when it is fulfilled it is *linked* to the
  real transaction that fulfilled it, rather than becoming one.
- **Wish:** the state before a date. An undated want, outside the forecast
  entirely until someone gives it a target date, which promotes it to a planned
  purchase. Defined in ADR 0021 along with projects, which group both wishes and
  real transactions across categories and periods.
- **A forecast is derived, never stored:** current balances from ADR 0011, plus
  commitments due in the horizon, plus planned purchases, projected forward as a
  balance timeline per account. It is a view, recomputed on every read, so it can
  never drift from the ledger.
- **Matching an expectation to reality reuses the reconciliation machinery** built
  for bank statements: an arriving transaction is matched against open
  commitments and planned purchases on the same account, amount and rough date.
  This is deliberately one mechanism, not three.
- **A missed commitment is a first-class state**, not an absence. If a
  commitment's due date passes with no matching transaction, that is surfaced —
  an unpaid bill is the most useful thing this module can tell anyone.

What the forecast is *for*, and therefore what the alerts are, follows from
ADR 0011's balances: a projected overdraft, a projected breach of an overdraft
limit, a budget exceeded, a commitment due with insufficient projected funds.
These arrive as Telegram pushes (ADR 0007), because a forecast nobody reads is
decoration.

## Alternatives

| Option | Why rejected |
|---|---|
| Posting expectations into the ledger as pending or scheduled transactions | The obvious design and the wrong one: balances, reports and the trial balance would include things that did not happen. The ledger's only asset is that it is true |
| A separate "forecast ledger" with its own postings, mirroring the real one | Double the schema, double the reconciliation, and two places for a number to be wrong. The projection is cheap to compute from the real ledger and a handful of expectation rows |
| Envelope budgeting, where budgeted money is moved between real accounts | A legitimate and popular method, and it *does* use postings — to equity sub-accounts. Rejected as more ceremony than this household will maintain; the category-and-period budget is the version people actually keep up |
| Budgets as a spreadsheet outside the system | Where household budgets go to die. It also cannot compare itself to actuals, which is the only reason to have a budget |
| Storing the computed forecast for speed | At this data volume the projection is milliseconds. A stored forecast is a cache that will be stale at the worst moment |
| A general task or project planner for the household | Out of scope by ADR: planning here means *purchases with dates and money*. Chores and calendars are a different product, and the vision explicitly defers household automation |

## Consequences

**Good:**
- The ledger stays truthful, and the forecast stays honest, because they are
  separate things that are joined only at read time.
- "Can we afford this in March" is answerable: balances plus commitments plus
  plans, projected.
- One reconciliation mechanism serves statements, commitments and plans.
- An unpaid bill surfaces itself.

**Bad, and the price we accept:**
- Two models to hold in mind — events and expectations — and reports that join
  them. The join is where subtle bugs will live, which is why it belongs in
  reviewed SQL views rather than in workflow logic.
- Fuzzy matching of expectations to real transactions will sometimes be wrong,
  and needs a cheap manual override in the app.
- Estimates for variable commitments (utilities) are guesses, so the forecast is
  only as good as they are. It should show them as estimates, not as facts.

**What becomes harder to change later:**
- Little on the ledger side, which is the point of keeping expectations out of it.
  Changing the budgeting *method* later — to envelopes, say — touches these
  tables and views only.
