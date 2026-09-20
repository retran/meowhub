---
id: 0012
title: Budgets, recurring commitments and planned purchases are forecast objects, never postings
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0012 - Budgets, recurring commitments and planned purchases are forecast objects, never postings

## Context

Running the household like a small firm means knowing what is coming as well as
what happened. Three requirements arrived together, and all three have the same
shape:

- Budgeting: how much this household intends to spend per category per month.
- Mandatory recurring expenses: rent or mortgage, utilities, insurance,
  subscriptions, and the loan payment from ADR 0011. The household knows them in
  advance, they barely move, and they are why a month is tight or comfortable.
- Planned purchases: things the household intends to buy, each scheduled on a
  date. This is the planning module, a list of intentions with dates and
  amounts, and it becomes real only when somebody actually buys something.

All three are *expectations*, while the ledger (ADR 0011) records *events*. The
tempting design is to post expectations into the ledger as pending or forecast
transactions so that one query answers everything, and it makes balances and
reports lie: a planned sofa would reduce the bank balance before anyone bought a
sofa, and the trial balance would assert something untrue.

## Decision

**Only things that happened become postings.** Budgets, commitments and planned
purchases live in their own tables and never touch the ledger. Seven rules
define them:

- A budget is an amount for a category, meaning an expense account subtree, for
  a period, with an optional rollover of the unspent remainder into the next
  period. We compare it against actual postings at read time, in SQL views.
- A commitment is a recurring obligation, with an amount or an estimate, a
  cadence, the account it is paid from, the category and a next-due date. A
  commitment *expects* a transaction and does not create one, and the loan
  amortization from ADR 0011 is a commitment whose expected split we compute
  instead of fixing.
- A planned purchase is a one-off intended spend with a target date, an
  estimated amount, a category and a priority. It moves through a lifecycle of
  `planned`, `done`, `dropped` and `postponed`, and when it is fulfilled we
  *link* it to the real transaction that fulfilled it instead of turning it into
  one.
- A wish is the state before a date: an undated want, outside the forecast
  entirely until somebody gives it a target date, which promotes it to a planned
  purchase. ADR 0021 defines it along with projects, which group both wishes and
  real transactions across categories and periods.
- A forecast is derived and never stored. It takes current balances from
  ADR 0011, adds commitments due in the horizon and planned purchases, and
  projects a balance timeline per account. It is a view, recomputed on every
  read, so it cannot drift from the ledger.
- Matching an expectation to reality reuses the reconciliation machinery we
  build for bank statements, so an arriving transaction is matched against open
  commitments and planned purchases on the same account, amount and rough date.
  We deliberately keep this as one mechanism and not three.
- A missed commitment is a state of its own and not an absence. When a
  commitment's due date passes with no matching transaction, the system says so,
  because an unpaid bill is the most useful thing this module can tell anyone.

What the forecast is *for* decides what the alerts are, and both follow from
ADR 0011's balances: a projected overdraft, a projected breach of an overdraft
limit, a budget exceeded, or a commitment due with not enough projected funds.
They arrive as Telegram pushes (ADR 0007), because nobody reads a forecast they
have to go and open.

## Alternatives

| Option | Why rejected |
|---|---|
| Posting expectations into the ledger as pending or scheduled transactions | The obvious design and the wrong one, because balances, reports and the trial balance would then include things that did not happen, and the ledger is worth having only while every row in it is true |
| A separate "forecast ledger" with its own postings, mirroring the real one | Double the schema, double the reconciliation, and two places for a number to be wrong, while the projection is cheap to compute from the real ledger and a handful of expectation rows |
| Envelope budgeting, where budgeted money is moved between real accounts | A legitimate and popular method, and it *does* use postings, to equity sub-accounts. We rejected it as more ceremony than this household will keep up, since a category-and-period budget is the version people actually maintain |
| Budgets as a spreadsheet outside the system | Households abandon those within a few months, and a spreadsheet cannot compare itself to actuals, which is the only reason to keep a budget |
| Storing the computed forecast for speed | At this data volume the projection takes milliseconds, so a stored forecast is a cache that will be stale at the worst moment |
| A general task or project planner for the household | Out of scope by ADR, because planning here means *purchases with dates and money*. Chores and calendars are a different product, and the vision defers household automation explicitly |

## Consequences

We gain four things:

- The ledger stays truthful and the forecast stays honest, because they are
  separate things joined only at read time.
- "Can we afford this in March" becomes answerable, from balances plus
  commitments plus plans, projected forward.
- One reconciliation mechanism serves statements, commitments and plans.
- An unpaid bill announces itself.

We accept three costs in return:

- Anyone working here holds two models in mind, events and expectations, and the
  reports join them. Subtle bugs will live in that join, which is why it belongs
  in reviewed SQL views instead of in workflow logic.
- Fuzzy matching between expectations and real transactions will sometimes be
  wrong, so the app needs a cheap manual override.
- Estimates for variable commitments such as utilities are guesses, so the
  forecast is only as good as they are and has to show them as estimates rather
  than as facts.

Little gets harder to change on the ledger side, which is the point of keeping
expectations out of it. Changing the budgeting *method* later, to envelopes for
example, touches these tables and views and nothing else.
