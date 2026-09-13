---
id: 0009
title: Budgets, commitments and the forecast
status: approved
created: 2026-09-12
updated: 2026-09-13
owner: admins
supersedes: []
---

# 0009 — Budgets, commitments and the forecast

## Problem

By now the books are complete and readable: the household knows what it spent and
what it owes. It still cannot answer the question people actually ask before
spending money — **can we afford this** — because nothing in the system knows what
is coming.

Two kinds of "coming" are missing. The mandatory monthly obligations — rent or
mortgage, utilities, insurance, subscriptions, the loan payment — are known in
advance and are the reason a month is tight or comfortable, yet they are invisible
until they happen. And there is no statement of intent: no budget to compare
against, so overspending is only ever discovered afterwards.

## Why

After this slice the household can look at the month ahead rather than the month
behind: what is committed, what is left, and whether a balance is heading below
zero. An unpaid bill announces itself instead of being discovered.

The measure: before a significant purchase, someone actually checks — and the
forecast is close enough to reality that they believe it.

## Users and scenarios

- **An admin** wants to know what is already spoken for this month.
- **A member** wants to know whether there is room for something before buying it.
- **An admin** wants to be told when a bill that should have been paid was not.
- **An admin** wants to set a budget for a category and see progress against it.
- **An admin** wants warning before an account goes into overdraft, not after.

## Requirements

### Budgets

- **R1.** An admin must be able to set a budget: an amount for a category, for a
  period, with optional rollover of the unspent remainder.
- **R2.** Budget progress must be computed from actual postings at read time, never
  stored (ADR 0012).
- **R3.** A budget report must show spent, remaining, and the proportion of the
  period elapsed, so "half the budget on day three" is visible as such.
- **R4.** Exceeding a budget must alert the admins once for that period.

### Commitments

- **R5.** An admin must be able to record a commitment: an amount or an estimate, a
  cadence, the account it is paid from, the category, and a next due date.
- **R6.** A commitment must expect a transaction without creating one.
- **R7.** The loan's amortisation schedule from spec 0008 must appear as a
  commitment with a computed split, not as a separately maintained record.
- **R8.** An arriving transaction must be matched against open commitments using
  the same reconciliation machinery as statement lines (ADR 0012).
- **R9.** A commitment whose due date passes with no matching transaction must
  become a **missed commitment** — a first-class state, surfaced, not an absence.
- **R10.** A variable commitment must be marked as an estimate wherever its figure
  appears, so the forecast does not present a guess as a fact.

### The forecast

- **R11.** A forecast must project each account's balance forward over a horizon
  from: current balances, open commitments due in the horizon, and planned
  purchases (spec 0010 adds those).
- **R11a.** Income must be modelled as a commitment too, so the projection
  includes salary rather than only outflows.
- **R12.** The forecast must be derived on every read and never stored.
- **R13.** The forecast must show, per account and per period: committed, budgeted
  but unspent, and the resulting projected balance.
- **R14.** A projected balance below zero, or below an overdraft limit, must alert
  the admins once, naming the date and the amount.
- **R15.** A member must be able to ask in chat whether a given amount fits this
  month, and receive an answer grounded in the forecast rather than an opinion.
- **R15a.** The slice's other figures must be askable in chat too: what is
  committed this month, what is still to come, what a budget has left, and what
  the projected balance is on a given date (spec 0004, R2a).
- **R16.** Every forecast figure must state that it is a projection and what it
  assumed.
- **R17.** The household's commitments must be collected by the agent in a
  resumable setup conversation, including income, and be editable afterwards.
- **R18.** The forecast horizon must default to the end of the next calendar
  month and be configurable.
- **R19.** Budget alerts must go to the admins only, and must never address the
  member whose spending crossed the budget.
- **R20.** A per-member "what is left" view belongs to this slice, since it is
  only meaningful against a budget or an allowance.

## Scope

**In scope:** budgets with rollover, commitments with cadences and matching,
missed-commitment detection, the projection views, the affordability question in
chat, the budget and forecast screens in the app, and the four alerts — budget
exceeded, projected overdraft, projected limit breach, commitment missed.

**Out of scope (and why):**
- Envelope budgeting, where money moves between accounts. Rejected in ADR 0012:
  it makes balances disagree with the bank.
- Wishes and projects (spec 0010). They feed the same forecast and arrive next.
- Income forecasting beyond recorded salary commitments. Predicting income is a
  different problem from knowing obligations.
- Automatic budget suggestions from history. Possible later; it needs a year of
  data to be anything but noise.
- Savings goals as balances to reach. A project's target covers this (spec 0010).

## Acceptance criteria

- [ ] **A1.** Given a monthly budget for a category and postings against it, when
      progress is read, then spent plus remaining equals the budget, and the
      elapsed proportion of the period is shown.
- [ ] **A2.** Given a budget with rollover and an unspent remainder, when the next
      period starts, then the remainder is added to it, and without rollover it is
      not.
- [ ] **A3.** Given spending that crosses a budget, when it is recorded, then the
      admins are alerted once for that period and not again.
- [ ] **A4.** Given a monthly commitment and a transaction matching it in amount,
      account and approximate date, when the transaction arrives, then the
      commitment is satisfied and its next due date advances.
- [ ] **A5.** Given a commitment whose due date passed with no match, when the check
      runs, then it is reported as missed, with its amount and the date it was due.
- [ ] **A6.** Given the loan from spec 0008, when commitments are listed, then its
      next payment appears with the expected principal and interest split, and it
      is not duplicated by a separate manual commitment.
- [ ] **A7.** Given current balances and a set of commitments, when the forecast is
      read for the next 60 days, then each account's projected balance equals the
      current balance less the commitments due in that window, and the arithmetic
      is reproducible by hand.
- [ ] **A8.** Given a forecast that dips below an overdraft limit, when it is
      computed, then the admins are alerted once, naming the date and the shortfall.
- [ ] **A9.** Given a member asking "can we spend 400 on a sofa this month", when
      answered, then the reply is grounded in the forecast, states what it assumed,
      and does not offer an opinion about the purchase.
- [ ] **A10.** Given a variable commitment, when it appears in the forecast or a
      report, then it is marked as an estimate.
- [ ] **A11.** Given no budgets and no commitments, when the forecast is read, then
      it returns current balances with a clear statement that nothing is committed
      — not an error and not an empty screen.
- [ ] **A12.** Given every figure in this slice, when compared between the bot and
      the app, then they are identical, because both read the same views.
- [ ] **A13.** Given a forecast, when it is read twice with no intervening change,
      then it is identical — and when a transaction is recorded, it changes
      accordingly, proving it is derived rather than cached.
- [ ] **A14.** Given budgets and commitments covering a whole year, when the ledger
      is inspected, then none of them has produced a posting, and no account
      balance differs from the sum of real transactions (ADR 0012). This is the
      invariant the whole slice rests on.
- [ ] **A15.** Given a setup conversation about commitments abandoned halfway, when
      the forecast is read, then it projects from what was collected and says so —
      a partial answer leaves a working forecast.
- [ ] **A16.** Given the default horizon, when the forecast is read, then it
      reaches the end of the next calendar month and includes at least one salary.
- [ ] **A17.** Given a member whose spending crosses a category budget, when the
      alert fires, then it reaches the admins and **not** that member.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A commitment paid early, before its due date | Matched; the due date advances; not reported missed |
| A commitment paid twice | Both recorded; the second is flagged rather than silently accepted |
| A commitment whose amount varies by more than tolerance | Matched with a warning, and the estimate updated from actuals |
| A commitment cancelled mid-year | Closed with an end date; history keeps it |
| A budget set mid-period | Pro-rated in the progress report, or shown against the whole period with the start date stated — never silently either way |
| A budget for a category that is also a project's spending | Both count it; they are different axes (ADR 0021) |
| A forecast horizon crossing a rate change on the loan | Uses the terms effective at each date |
| Overlapping alerts — budget exceeded and overdraft projected in the same hour | Separate conditions, separate messages, each once |
| Income arriving later than assumed | The forecast is a projection and says so; no alert for an assumption not holding |

## Ergonomic cost

- **Who does more work:** an admin, once, entering the household's commitments —
  perhaps a dozen — and any budgets they want. Budgets are optional; commitments
  are what make the forecast worth anything.
- **What queue or obligation it creates:** missed commitments. It is intended to
  be short and actionable; if it grows, the commitment data is wrong, and that is
  itself the signal.
- **What it interrupts, and how often:** four alert kinds, each once per condition.
  This is the slice most capable of overspending the interruption budget in
  `docs/standards/ergonomics.md`, so each alert must be actionable or it is a
  defect.
- **If nobody touches it for a month:** commitments keep matching, missed ones keep
  surfacing, and the forecast stays derived and correct. Stale commitment amounts
  degrade the forecast gradually, which is why actuals update estimates.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **The forecast is fast enough to be read on demand**, because caching it would
  let it drift from the ledger.
- **No model is involved in the numbers.** The model maps a question; the
  projection is SQL.
- **Alerts are once per condition, never repeated without new information.**
- **The forecast never overstates certainty**: estimates are labelled everywhere.

## Open questions

None. Everything this slice needed decided has been decided; what the household
must still supply is listed in spec 0001 and spec 0002.

## Related

- ADRs: 0011, 0012, 0013, 0020, 0021, 0022, 0023
- Specs: 0008 (must be done first), 0010 (adds plans to the same forecast)
