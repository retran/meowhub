---
spec: 0009
created: 2026-09-13
updated: 2026-09-13
---

# 0009 - Implementation plan

> This plan answers how. When the plan and the spec disagree, we fix the spec
> first and then the plan.

## Approach

We build commitments first, then the projection, then budgets. The order follows
from what the household gets: the forecast is the point of the slice, commitments
are what make a forecast worth reading, and the household can live without
budgets in a way it cannot live without commitments. Starting with budgets would
give us a screen comparing spend to an intention while nobody could yet answer
the question people ask, which is what is already spoken for this month.

Everything in this slice is expectation, so ADR 0012's rule holds without
exception: **no row in this slice ever produces a posting.** We write that
invariant as a pgTAP test before the first table is used rather than asserting it
at the end, because the whole slice rests on it (A14) and a well-meaning later
change is more likely to break it than anything else here.

1. **`commitment`** - amount or estimate, cadence, account, category, next due,
   expense or income (R5, R11a). The agent collects them in a conversation that
   can be resumed, reusing spec 0003's `conversation` machinery (ADR 0038, R17),
   and an admin can edit them afterwards by hand or in chat.
2. **Matching** through spec 0007's matcher, so the household never gets two
   answers to "is this the same money" (R8). We generalise the matcher there into
   one SQL function over (account, amount, date within tolerance); this slice
   becomes its second caller, and both callers are tested against it.
3. **Missed commitments** as a first-class state on `v_commitment` (R9), derived
   from "due date passed, nothing matched", which turns an absence into a row
   somebody can read.
4. **`v_forecast`**, derived on every read (R12): current balances from
   `v_account_balance`, plus commitments due inside the horizon, projected per
   account per period. Spec 0010's planned purchases join the same union later,
   so we give the view room for a third source from the start.
5. **The affordability question** in chat (R15) as a read tool the agent calls
   like any other (ADR 0046). The tool reads the forecast view and computes no
   figure of its own (spec 0004, R4a/R5).
6. **`budget`** with rollover, and `v_budget_progress`, which compares it to
   actual postings at read time (R1-R3).
7. **The four alerts**, evaluated by one scheduled sweep, each fired once per
   condition and only to admins (R4, R14, R19).
8. **The per-member "what is left" figure** (R20). It means nothing until a
   budget exists, which is why it comes last.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Expectations in their own tables, joined to the ledger only at read time | The ledger stays true; the forecast cannot drift from it; one reconciliation mechanism serves statements and commitments alike | Two models to hold in mind, and the join is where subtle bugs will live | **chosen** (ADR 0012) |
| Post expectations into the ledger as pending transactions | One query answers everything | Balances would include things that did not happen, and the ledger's only asset is that it is true | rejected in ADR 0012 |
| Store the computed forecast for speed | Constant-time reads | A cache goes stale at the worst moment, and at this data volume the projection takes milliseconds | rejected in ADR 0012, restated by R12 and tested by A13 |
| A second matcher for commitments, separate from spec 0007's | Simpler to write in isolation | Two implementations of "is this the same money" will disagree, and the household sees the disagreement as a bill reported missed that was paid | rejected, because R8 asks for the same machinery, and one function with two callers delivers it |
| Evaluate budget crossing synchronously inside the capture workflow | The alert lands the instant it happens | Couples the capture path to alerting and spends its latency budget (spec 0003 NFR: a confirmation within a few seconds) on a message nobody needs within the minute | rejected in favour of one sweep, in one place, on one heartbeat |
| Hand-enter the loan payment as an ordinary commitment | No derivation code | Two records of one obligation, drifting apart the first time a rate changes, which is what A6 exists to forbid | rejected; the loan commitment is derived from `account_term` |
| Pro-rate a budget set mid-period | The percentage looks right on day one | Arithmetic nobody asked for, done silently, which the spec's edge case forbids | rejected; we show the whole-period amount with its start date exposed, and the caller says "from 12 March" |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `db/migrations/` | `budget`, `commitment`, `alert_state`; the views below; RLS and grants for each (admins write, everyone reads, per ADR 0016) | spec 0010 adds `planned_purchase` to the same forecast |
| `db/tests/` | The no-postings invariant, budget rollover arithmetic, commitment matching and missed detection, forecast determinism | every later slice that touches a forecast input |
| `docs/architecture/data-model.md` | Three catalogue changes, listed under *Contracts and data*; the migration and the catalogue entry land in one commit | spec 0010 |
| `workflows/` | The commitment setup conversation; the affordability question; the scheduled alert sweep and its heartbeat | spec 0010 adds wishes to the same question set |
| `prompts/` | Whatever this slice's tools need naming in the agent's one system prompt (ADR 0046), and no prompt of its own (ADR 0025) | spec 0010 |
| `tools/` | Declared tools for creating, editing and closing commitments and budgets, admin-only (ADR 0039) | spec 0010 |
| App (spec 0006) | The budget screen and the forecast screen, from the same views the bot reads | - |
| `docs/guides/talking-to-meow.md` | This slice's questions added to the documented answerable set (spec 0004, R23) | every later slice |
| `docs/guides/household-setup.md` | What the commitment interview asks, so an admin knows what to have to hand | spec 0010 |

## Contracts and data

- **`budget(id, account_id, period_kind, starts_at, amount_minor, currency,
  rollover, active)`** - `account_id` is an expense account, because a category
  *is* an expense account in the data model. The table stores no progress of any
  kind.
- **`commitment(id, name, account_id, category_account_id, amount_minor,
  is_estimate, direction, cadence, next_due_on, starts_on, ends_on, active)`** -
  `direction` is `expense` or `income` (R11a), and `ends_on` closes a cancelled
  commitment without deleting its history.
- **`alert_state(id, kind, subject_key, period_key, fired_at, cleared_at)`**
  records that a condition has already been announced. It holds one row per
  (kind, subject, period), and the sweep inserts, so it cannot insert twice. This
  table is what makes "once per condition" (R4, R14) testable rather than hoped
  for.
- **`v_commitment`** lists obligations with next due, estimate flag and **missed**
  state, per the catalogue. The loan's next payment appears here derived from
  spec 0008's `account_term` with its computed principal and interest split (R7),
  unioned with hand-entered rows and never duplicated (A6).
- **`v_budget_progress`** gives spent, remaining, the proportion of the period
  elapsed, and the budget's `starts_at`. Rollover is a recursive CTE over periods
  from the budget's start, bounded there, so an unspent remainder carries forward
  without anything being written down.
- **`v_forecast`** gives the projected balance per account over the horizon. The
  catalogue describes it as balances only, and R13 needs `committed` and
  `budgeted_unspent` alongside `projected_balance`, so this slice extends the
  catalogue entry instead of adding a second view. It left-joins from accounts,
  so an account with nothing committed returns a row with zeroes and an explicit
  `commitment_count`, which makes A11's "nothing is committed" a value rather
  than an empty result the caller has to interpret.
- **The horizon** defaults to the end of the next calendar month (R18). It is a
  parameter carrying that default, configurable per ADR 0034, because it is a
  deployment setting and not a constant in a workflow.
- **Money is integer minor units with an explicit currency** in every table and
  every view, as the data model requires throughout.

## Migration and compatibility

- Nothing that exists changes shape. This slice adds tables and views and alters
  no ledger table, which follows from ADR 0012 and is why the slice is safe to
  add this late.
- Every migration has a `down`, so the change is reversible: dropping these
  tables leaves the ledger byte-identical, which A14 also proves from the other
  direction.
- `v_forecast`'s signature is a public interface, as the data model requires.
  Spec 0010 adds planned purchases as a third source, so we choose the view's
  columns now to take that source without a signature change, and the snapshot
  test guards them.
- Spec 0008 must be built first, as its spec says: `account_term` and the
  amortisation derivation are its contract, and R7 consumes them. If spec 0008
  slipped, this slice still builds, and the loan then appears as no commitment at
  all rather than as a wrong one.

## Verification strategy

We test the arithmetic with pgTAP against a real PostgreSQL, seeded with fixtures
whose totals we compute by hand in the test's own comments, because a view that
agrees with itself proves nothing (ADR 0015). Anything crossing the boundary is a
real request against the running stack through PostgREST or the bot, which is the
pattern every `scripts/test-*.sh` in this repository already follows, wired into
`task test`.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | pgTAP `…_budgets.sql`: a budget and postings against it; assert spent + remaining = amount, and the elapsed proportion against a frozen clock |
| A2 | pgTAP `…_budgets.sql`: two consecutive periods, one budget with rollover and one without; assert the remainder carries in the first case and does not in the second |
| A3 | `scripts/test-forecast-alerts.sh`: spend past a budget, run the sweep twice; assert exactly one message, and that a second sweep with no new crossing sends nothing |
| A4 | pgTAP `…_commitments.sql`: a matching transaction on account, amount and date within tolerance; assert the commitment is satisfied and `next_due_on` advances by its cadence |
| A5 | pgTAP `…_commitments.sql`: a due date passed with nothing matching; assert `v_commitment` reports it missed, with amount and due date |
| A6 | pgTAP `…_commitments.sql`: with spec 0008's loan and terms present, assert exactly one row for the next payment, carrying the expected principal/interest split, and that adding a hand-entered duplicate is refused |
| A7 | pgTAP `…_forecast.sql`: known balances and commitments over 60 days; the expected figures are written out longhand in the test and compared, so the arithmetic is reproducible by hand as the criterion demands |
| A8 | `scripts/test-forecast-alerts.sh`: commitments driving a projected balance under an overdraft limit; assert one alert naming the date and the shortfall, and none on the second sweep |
| A9 | `scripts/test-affordability.sh`: ask "can we spend 400 on a sofa this month" through the bot; assert the reply's figure equals `v_forecast` read directly, that it states its assumptions and horizon, and that it contains no opinion about the purchase (checked against the persona's forbidden registers) |
| A10 | pgTAP `…_commitments.sql`: an estimate commitment; assert `is_estimate` surfaces in `v_commitment` and in `v_forecast`'s contribution, not only on the source row |
| A11 | pgTAP `…_forecast.sql`: no budgets, no commitments; assert a row per account with `commitment_count = 0` and the current balance, rather than an empty result or an error |
| A12 | `scripts/test-figures-agree.sh`: for each question this slice adds, the bot's answer compared with a direct PostgREST read of the same view and parameters, which is the app's own path, asserted equal |
| A13 | pgTAP `…_forecast.sql`: read twice, assert identical; record a transaction, read again, assert it changed by exactly that amount |
| A14 | pgTAP `…_expectations_create_no_postings.sql`: a year of budgets, commitments and their matching across period boundaries; assert `posting` gained no row attributable to any of them, and every account balance still equals the sum of its real transactions. The slice's load-bearing test |
| A15 | `scripts/test-commitment-setup.sh`: drive the conversation partway, abandon it, read the forecast; assert it projects from what was collected and says so, and that resuming continues from the same step after a container restart (ADR 0038) |
| A16 | pgTAP `…_forecast.sql`: default horizon; assert it reaches the end of the next calendar month and includes at least one income commitment |
| A17 | `scripts/test-forecast-alerts.sh`: a non-admin member's spending crosses a category budget; assert the message reaches both admins' channels and not that member's |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A forecast that is confidently wrong is worse than none | high | Estimates are labelled everywhere they appear (R10, A10), actuals update estimates, every figure states that it is a projection and what it assumed (R16), and A7's arithmetic is reproducible by hand, so a wrong number can be traced to its input |
| Alert fatigue, because four new alert kinds land in the slice most able to overspend the interruption budget | high | `alert_state` makes "once per condition" a database fact rather than workflow discipline; admins only (R19); one sweep rather than four schedules; and the spec's own rule that an alert nobody can act on is a defect |
| The commitment matcher and the statement matcher drift apart | medium | One SQL function, two callers, and pgTAP exercising it from both sides, which prevents a bill being reported missed after it was paid |
| Stale commitment amounts degrade the forecast quietly | medium | Actuals update estimates on match (the spec's edge case table), and a variance beyond tolerance is matched with a warning instead of silently |
| Rollover's recursive CTE grows unbounded or gets slow | low | Bounded at the budget's `starts_at`; A2 and A14 both exercise a full year |
| Spec 0010 forces a `v_forecast` signature change | medium | We design the union's third source in now and snapshot the signature, so spec 0010 adds rows to the union rather than columns to the contract |
| `alert_state` becomes a second place "what is true" lives | low | It records only that something was announced, never a financial fact; nothing reads it to compute a figure, and dropping it would lose no money data |

## ADRs required

- **Candidate: an alert is a condition with state, announced once.** Three slices
  now need it - this one's four alerts, ADR 0023's unconfirmed-queue ceiling, and
  spec 0008's limit warning - and each has so far described the behaviour in
  prose without naming the machinery. If `alert_state` survives this slice
  unchanged, we should write it up rather than derive it a fourth time in spec
  0010.
- Nothing else. ADR 0012 already decided the whole shape of this slice, so this
  plan implements a decision instead of making a new one.
