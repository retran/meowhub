---
id: 0008
title: Borrowing — card settlement, overdraft interest, fees and loans
status: approved
created: 2026-09-12
updated: 2026-09-13
owner: admins
supersedes: []
---

# 0008 - Borrowing: card settlement, overdraft interest, fees and loans

## Problem

The household borrows in three ways - a credit card, an overdraft on the current
accounts, and a loan - and each one costs money that a spending report doesn't
show.

The accounts for all of this exist from spec 0003, and spec 0007 posts individual
interest and fee lines correctly as they arrive. What's missing is the structure
around them: nobody can answer "what does credit cost us in a year", nobody knows
the loan's payments in advance, so nobody can forecast them, and splitting each
payment between principal and interest means working it out by hand from a
statement line.

This slice prevents the most common error in household bookkeeping: treating a
loan repayment as an expense, which inflates spending, understates net worth, and
makes every trend meaningless.

## Why

After this slice the household reads the cost of borrowing off a report instead
of guessing at it, knows the loan's schedule in advance, and gets each payment
split automatically.

We measure it two ways: the household can say what credit cost last year, and the
loan's outstanding balance in the books matches the lender's statement.

## Users and scenarios

- **An admin** wants to know what the household pays in interest and fees per
  year, and on what.
- **An admin** wants the loan's remaining principal to be right without arithmetic.
- **An admin** wants a loan payment to split into principal and interest
  automatically.
- **An admin** wants to know how close an account is to its overdraft limit.
- **An admin** wants a cash withdrawal on the card to show its fee as a cost, not
  as part of the amount withdrawn.

## Requirements

### Structure

- **R1.** A liability account must be able to carry its terms: a credit limit for
  a card, an overdraft limit for a current account, and, for a loan, its original
  principal, interest rate, payment amount, and payment day.
- **R1a.** Terms must carry an effective date, so that a rate or payment change is
  recorded as a new term and nothing rewrites history.
- **R2.** The system must be able to derive a loan's amortisation schedule from
  its terms, giving the expected principal and interest split for each future
  payment.
- **R3.** The schedule must be a forecast object rather than postings, and the
  system must record nothing until a payment happens (ADR 0012).
- **R4.** A loan payment must be recorded as one transaction split into principal,
  which reduces the liability, and interest, which is an expense (ADR 0011).
- **R5.** When the actual split differs from the schedule, the system must keep the
  actual figures and re-derive the schedule from the new outstanding balance.
- **R6.** A cash withdrawal on the card must be one transaction: cash up, card
  liability up by principal plus fee, and the fee to its own expense account.
- **R7.** Interest and fees must post to a dedicated account subtree, so that cost
  of credit is a query rather than a reconstruction.
- **R8.** Paying the card bill must stay a transfer and must never appear in
  spending (spec 0007, R15).

### Reporting

- **R9.** A report must give total cost of credit for a period, broken down by
  instrument and by kind: interest, fees, charges.
- **R10.** A report must give each liability's outstanding balance, derived from
  postings.
- **R11.** An account with an overdraft limit must report its available headroom.
- **R12.** The loan's report must show principal paid, interest paid, and
  remaining principal, for any period.
- **R13.** Every figure must come from a SQL view, and the bot and the app must
  read the same ones, named in
  [docs/architecture/data-model.md](../../docs/architecture/data-model.md),
  including `v_cost_of_credit`, which this slice introduces.
- **R13a.** Every figure in this slice must be askable in chat rather than only
  visible in the app: what the household owes in total and per instrument, what
  credit cost over a period, how much headroom is left against each limit, and
  what remains on the loan. These join the mapped question set (spec 0004, R2a).

### Alerting

- **R14.** Crossing a configurable proportion of an overdraft or credit limit must
  alert the admins once, with the number and the headroom left (ADR 0020).
- **R15.** The system must surface a scheduled loan payment that doesn't appear
  within a tolerance of its due date as a missed commitment (ADR 0012).
- **R16.** The agent must collect each liability's limit and terms during setup,
  an admin must be able to change them afterwards (ADR 0031), and no limit may be
  hard-coded.
- **R17.** The limit alert must fire at 80% of a limit by default and must be
  configurable per account.
- **R18.** The monthly digest must carry one line of cost of credit, and the
  weekly digest must carry none.

## Scope

In scope: liability terms on accounts, the amortisation schedule as a forecast
object, the payment split and its correction from actuals, cash-advance fee
handling, the interest and fee account subtree, cost-of-credit and liability
reports, overdraft headroom, and the limit and missed-payment alerts.

Out of scope, with the reason for each:

- Mortgages with escrow, offsets, or variable-rate resets. We model the
  household's loan, and a mortgage of that complexity is its own decision.
- Early repayment planning and refinancing comparisons.
- Interest accrual between statements, because recognition is cash basis
  (ADR 0011) and we record interest when it is charged.
- Investment or savings return, because this slice is about what borrowing costs.
- Multi-currency debt.

## Acceptance criteria

- [ ] **A1.** Given a loan with principal, rate, payment and day, when its schedule
      is derived, then the principal and interest split of each payment sums to the
      payment amount and the final payment clears the principal.
- [ ] **A2.** Given a loan payment on the statement, when imported, then one
      transaction exists with a principal posting against the liability and an
      interest posting against the interest account, and the month's spending
      total includes the interest but not the principal.
- [ ] **A3.** Given a payment whose actual split differs from the schedule, when it
      is recorded, then the actual figures are kept and the remaining schedule is
      re-derived.
- [ ] **A4.** Given a cash withdrawal of 200 EUR with a 4 EUR fee, when recorded, then
      cash rises by 200 EUR, the card liability rises by 204 EUR, the fee expense is
      4 EUR, and spending for the period rises by 4 EUR and not by 204 EUR.
- [ ] **A5.** Given interest charged on an overdraft, when imported, then it posts
      to the overdraft interest account and appears in cost of credit, not in any
      spending category.
- [ ] **A6.** Given a year of card, overdraft and loan activity, when the cost of
      credit report is run, then it equals the sum of the interest and fee
      accounts for that year, broken down by instrument.
- [ ] **A7.** Given the loan, when its outstanding principal is reported, then it
      equals the original principal less the principal postings, and matches the
      lender's statement for the same date.
- [ ] **A8.** Given an account at 85% of its overdraft limit with a threshold of
      80%, when the balance is updated, then the admins are alerted once with the
      headroom stated, and not again while the condition persists.
- [ ] **A9.** Given a loan payment that does not arrive within its tolerance, when
      the check runs, then it is surfaced as a missed commitment.
- [ ] **A10.** Given the seeded household, when every figure in this slice is
      compared between the bot and the app, then they are identical.
- [ ] **A11.** Given a loan with a full amortisation schedule, when the ledger is
      inspected, then the schedule has produced **no postings at all** - only
      actual payments are recorded (ADR 0012).
- [ ] **A12.** Given an account whose limit was collected at setup, when an admin
      changes it, then the change applies and is audited - no limit is hard-coded.
- [ ] **A13.** Given the monthly digest, when it renders, then it carries one line
      of cost of credit; and given the weekly, then it does not.
- [ ] **A14.** Given each figure this slice adds, when it is asked for in chat,
      then it is answered - and the answer matches the app's figure for the same
      period, because both read the same view.

## Edge cases and failures

The states below are named from
[docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| An interest-only period, or a payment holiday | The actual postings stand, and the schedule re-derives from the outstanding balance |
| An extra, unscheduled repayment | Recorded as principal, and the schedule shortens |
| A rate change mid-loan | The terms are updated with an effective date, and the schedule re-derives from there |
| A statement line combining principal and interest with no breakdown | Flagged for review rather than split by guess, with the schedule's expected split offered as a suggestion |
| A refund of a fee | A negative posting to the same fee account |
| An overdraft crossed and recovered within a day | The alert fires once on crossing, and recovery raises no alert |
| A card with no limit recorded | Headroom is unknown and reported as unknown rather than as zero |
| A loan fully repaid | The liability reaches zero, the schedule ends, and the account stays in the books |

## Ergonomic cost

- **Who does more work:** an admin, once, entering each instrument's terms. After
  that the slice removes work, because the split that was manual becomes
  automatic.
- **What queue or obligation it creates:** flagged payments where a statement
  gives no breakdown. They are rare, and the same review that drains spec 0007's
  flags drains them.
- **What it interrupts, and how often:** only a real condition, which is a limit
  crossed or a payment missed, and each one interrupts once.
- **If nobody touches it for a month:** payments still import and split from the
  schedule, and the reports stay correct. A missed payment surfaces itself, which
  is the point of the check.

## Non-functional requirements

The figures below refine the shared baselines in
[docs/standards/budgets.md](../../docs/standards/budgets.md): a figure here is
stricter and says so, and where this section is silent the baseline applies.

- **Arithmetic:** money is exact, in integer minor units, and a schedule's
  rounding is reproducible rather than drifting by cents.
- **Cost:** no model runs anywhere in this slice, which is arithmetic and SQL.
- **Terms:** they are configuration data, versioned with an effective date, so a
  rate change doesn't rewrite history.

## Open questions

None. We have decided everything this slice needed decided, and spec 0001 and
spec 0002 list what the household still has to supply.

## Related

- ADRs: 0011, 0012, 0013, 0020, 0022
- Specs: 0007 (must be done first), 0009 (consumes the schedule as a commitment)
