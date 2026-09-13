---
spec: 0008
created: 2026-09-13
updated: 2026-09-13
---

# 0008 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

Everything in this slice is arithmetic and SQL — no model is called anywhere
(the spec's own non-functional requirement), so there is no prompt, no golden
set and no cost ceiling to build. What there is instead is one structural
decision that the rest follows from: **the amortisation schedule is a view
derived from the loan's actual outstanding balance, not a stored table.**
ADR 0012 already requires a forecast to be derived rather than stored; making
the schedule a view rather than rows means A11 ("the schedule has produced no
postings at all") is true by construction rather than by discipline, and R5's
"re-derive from actuals" stops being a step anybody performs — it is simply
what the view does on the next read.

The order is the same bottom-up shape as spec 0002: build the thing that is
depended on before the thing that depends on it, and close each criterion
against the seeded household rather than a fixture invented for the test.
Spec 0001's seed already contains a card settlement, a cash-advance fee,
overdraft interest and a loan payment split, so most of this slice's fixtures
exist and need only the loan's terms added.

1. **`account_term`** — limits, rate, payment amount and day, with an
   effective date; append-only, so a rate change is a new row (R1, R1a).
2. **The interest and fee subtree**, identified by reserved slugs rather than
   by name, so cost of credit is a query and not a reconstruction (R7).
3. **`v_loan_schedule`** — the derived schedule, and the pgTAP test that it
   creates nothing (R2, R3).
4. **The payment split and the cash advance** as write paths, both through
   spec 0007's review flow rather than a silent guess (R4, R5, R6).
5. **The reporting views**: `v_cost_of_credit` (new here), and the term-derived
   columns on the balance views (R9–R12).
6. **The two alerts** from the scheduler container, each firing once per
   condition, each with a heartbeat (R14, R15, R17).
7. **The bot and the app**, reading the same views (R13a).

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| The schedule as a view derived from the liability's actual balance | A11 holds structurally; R5's re-derivation is free; nothing to keep in step with the ledger | Recomputed on every read | **chosen** — at one loan and ~60 periods the cost is nothing |
| A `loan_schedule` table, generated when terms are set and regenerated on drift | A schedule is queryable without a recursive CTE; the expected split is a row the importer can join to | A stored forecast is a cache that goes stale at the worst moment (ADR 0012 says exactly this), and rows that look like transactions are one careless join from becoming them | rejected |
| A set-returning function over RPC rather than a view | Takes an `as_of` parameter naturally | The catalogue in `data-model.md` is a catalogue of *views*, and PostgREST filters a view on `account_id` just as well | rejected |
| Identify the interest and fee accounts by name prefix (`Expenses:Interest:%`) | No new column | Names are renameable by an admin (ADR 0031); cost of credit would silently lose an account the day someone renamed it | rejected |
| Auto-split a statement line that gives no breakdown, using the schedule | No review queue | The spec's own edge case forbids it: flagged for review, the schedule offering the expected split as a suggestion | rejected |
| Defer the missed-payment check to spec 0009, which owns commitments | Keeps this slice smaller | R15 and A9 are this slice's criteria, and ADR 0012 already calls the loan payment a commitment whose split is computed | rejected — see "Contracts and data" |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `db/migrations/` | `account_term`; the interest and fee subtree seeded with reserved slugs; `v_loan_schedule`, `v_cost_of_credit`; term columns added to `v_account`, `v_account_balance`, `v_liability_summary`; the minimal `commitment` row for the loan | spec 0009 generalises `commitment` and adds `v_forecast` |
| `db/seed/household.sql` | The loan's terms and the card's limit, so the seeded household exercises every figure | — |
| `workflows/` | The loan-payment split and the cash-advance shape as declared tools (ADR 0039), reached from spec 0007's reconciliation review | — |
| `scheduler/docker/crontab` | The limit check and the missed-payment check, both with heartbeats | spec 0009 adds the budget and forecast alerts to the same jobs |
| `scripts/` | `check-limit-alerts.sh`, `check-missed-commitments.sh`, and their tests; `configure-monitoring.sh` gains two push monitors | — |
| `prompts/` | The question mapping gains this slice's queries (spec 0004 R2a) | every slice that adds a view |
| `docs/architecture/data-model.md` | **Extended first**: `v_loan_schedule` and the loan-position figure are not in the catalogue today | — |
| `docs/guides/talking-to-meow.md`, `household-setup.md` | The new questions; what terms setup collects | spec 0009 |

## Contracts and data

- **`account_term(id, account_id, effective_from, credit_limit_minor,
  interest_rate_bp, original_principal_minor, payment_amount_minor,
  payment_day, alert_threshold_bp, currency, created_at)`.** The rate is
  **basis points as an integer** and every intermediate is `numeric`; no
  floating point anywhere, so a schedule is reproducible to the cent.
  `alert_threshold_bp` defaults to 8000 and is per-account (R17). The current
  term for a date is the latest row by `(effective_from desc, id desc)` — two
  rows sharing an effective date means the later insert corrects the earlier,
  which is how the audit log already reads it.
- **`account_term` is append-only to application roles**, using the same deny
  trigger `audit_log` already has (`audit_log_deny_mutation()`). R1a stops
  being a convention: history cannot be rewritten because an update is refused.
- **The interest and fee subtree** is two accounts seeded with reserved,
  language-neutral slugs (`expenses.interest`, `expenses.fees`) whose
  descendants are found recursively. An admin may add a fee account under
  either and it counts from that moment without anything being changed here.
- **`v_cost_of_credit(period_start, period_end, instrument_account_id, kind,
  amount_minor, currency, unconfirmed_minor)`** — `kind` is `interest`, `fee`
  or `charge`, derived from which subtree root the posting's account descends
  from. The **instrument** is the counterpart posting's account in the same
  transaction; where a transaction has more than one non-charge posting the
  liability side wins, and a transaction with no liability or asset counterpart
  is attributed to nothing and flagged rather than guessed.
- **Headroom stays a column of `v_account_balance`**, never a view of its own
  (`data-model.md` deleted `v_headroom` for exactly this reason). An account
  with no limit recorded reports headroom as **null**, and every caller renders
  that as unknown rather than zero — the spec's own edge case.
- **`v_loan_schedule` is a catalogue addition.** It is not in
  `data-model.md` today, and that document's own rule is that a figure is added
  there first. So is R12's loan position — principal paid and interest paid for
  a period alongside remaining principal — which no catalogued view answers
  (`v_liability_summary` gives the balance, `v_cost_of_credit` the interest,
  and principal paid for a period is nowhere). **Both are extended into
  `data-model.md`, and spec 0008's R13 updated to name them, before the first
  migration is written.** Spec first, then the plan, then the code.
- **`commitment` arrives here, one slice early.** R15 requires a missed loan
  payment to surface as a missed commitment, and ADR 0012 already describes the
  loan payment as a commitment whose split is computed. This slice creates the
  table in the shape `data-model.md` catalogues and one row for the loan;
  **spec 0009 extends it and must not re-create it.**
- **Interest is an expense, and that is not a contradiction.** A2 wants the
  month's spending total to include interest; A5 wants it out of any spending
  *category*. Both hold because the subtree is expense accounts: interest
  counts in `v_period_spend`, and appears in `v_category_spend` under its own
  subtree, never mixed into a household category.
- **Sign conventions belong to spec 0003.** Every assertion in this slice is
  written against reported figures — `v_account_balance`, `v_period_spend` —
  rather than raw posting signs, so nothing here re-decides them.

## Migration and compatibility

- Additive: `account_term` and `commitment` are new tables, the subtree is new
  seeded rows, and no existing posting is rewritten. Every migration has a
  `down`.
- **Extending `v_account`, `v_account_balance` and `v_liability_summary`
  changes their signatures**, which the snapshot test (ADR 0015) will fail
  on. That failure is the mechanism working: the snapshot is updated in the
  same commit as the migration, so the change is deliberate and reviewed.
- No feature flag. There is nothing to roll out gradually: until terms are
  entered, every term-derived figure reports null, which is the correct answer
  for an account whose limit nobody has recorded.

## Verification strategy

Ledger arithmetic is pgTAP against the seeded household, asserted from the
views rather than from the postings, so a sign convention change in spec 0003
cannot quietly turn these green. Alerts are shell tests that run the real
scheduled job twice and inspect what it sent. Bot-versus-app equality is a
request through the real proxy path compared against a direct PostgREST read
of the same view. Every test is a `scripts/test-*.sh` or a `db/tests/*.sql`
wired into `task test`.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | pgTAP `loan_schedule`: every row's principal plus interest equals the payment amount, and the final row's principal equals the outstanding balance before it — the schedule clears |
| A2 | pgTAP: import the seeded loan payment; assert one transaction, a principal posting against the liability and an interest posting in the subtree, and that `v_period_spend` for the month moves by the interest and not by the principal |
| A3 | pgTAP: post a payment whose split differs from the schedule; assert the actual postings are kept unchanged and `v_loan_schedule` for the following period is derived from the new balance — nothing is corrected because nothing was stored |
| A4 | pgTAP: record the 200 € / 4 € cash advance; assert cash rises 200, the card's owed amount rises 204, the fee account holds 4, and `v_period_spend` for the period rises by exactly 4 |
| A5 | pgTAP: overdraft interest appears in `v_cost_of_credit` with `kind = interest` and the correct instrument, and `v_category_spend` places it under the interest subtree and under no household category |
| A6 | pgTAP: `v_cost_of_credit` aggregated over a seeded year equals a direct recursive sum over the interest and fee subtree, and its per-instrument breakdown sums to the same total |
| A7 | pgTAP for the arithmetic: outstanding equals original principal less the principal postings. The lender half — that it matches a real statement for the same date — is a **documented manual check, performed once against a real loan statement and recorded with its date**, the same way spec 0002 T14 recorded its break-glass rehearsal |
| A8 | `scripts/test-limit-alert.sh`: drive a seeded account to 85 % of an 80 %-threshold limit, run the real check job twice, assert exactly one admin report carrying the headroom figure, none on the second run, and a heartbeat pushed both times |
| A9 | The same script: a loan commitment due past its tolerance with no matching transaction; assert it is surfaced as missed, once |
| A10 | `scripts/test-borrowing.sh`: for each figure this slice adds, the bot's answer for the seeded household is compared byte-for-byte on the number against a direct PostgREST read of the same view |
| A11 | pgTAP: snapshot `count(*)` from `posting`, read `v_loan_schedule` over the loan's whole remaining term, assert the count is unchanged — the ADR 0012 test, written by attacking it rather than by reading the view's definition |
| A12 | pgTAP: an admin inserts a term with a later effective date; assert the new limit applies, the old row survives, both are in `audit_log`, and an `update` or `delete` on `account_term` is refused. Plus a grep over `db/migrations/` and `workflows/` asserting no limit, rate or threshold literal appears outside `account_term` |
| A13 | `scripts/test-borrowing.sh`: render both digests for the seeded household; assert the monthly carries exactly one cost-of-credit line and the weekly carries none |
| A14 | The same script, enumerating every figure R13a names — owed in total and per instrument, cost over a period, headroom per limit, what remains on the loan — rather than sampling one |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The derived schedule disagrees with the lender's own arithmetic by cents or by convention (day count, rounding direction, payment ordering) | **high** — this is the real risk in the slice | Actuals always win (R5), and the schedule is only ever a suggestion at the write path (the spec's own edge case). The rounding rule is stated in the migration and pinned by A1's pgTAP, and A7's one-time manual check against a real statement is what catches a convention mismatch before anyone trusts the figure |
| A limit is crossed and recovered between two runs of the scheduled check, so the crossing is never reported | medium | One function, two callers: the scheduler runs it on a schedule as the backstop, and spec 0007's import-apply and spec 0003's capture-confirm paths call the same function at the end of a write. Promptness comes from the write path; completeness from the schedule |
| `commitment` arriving here is shaped for the loan alone and spec 0009 has to change it under live data | medium | Build it in the shape `data-model.md` already catalogues — name, account, category, amount or estimate, cadence, next due, expense or income — not in the shape the loan alone needs |
| The catalogue gaps (`v_loan_schedule`, the loan position) get invented in a migration instead of agreed in `data-model.md` | medium | They are the slice's first task, before any migration, and the spec's R13 is updated in the same change |
| Extending three existing views breaks callers written by specs 0004 and 0006 | low | Columns are added, never renamed or removed; the signature snapshot makes any accidental removal a failing test |

## ADRs required

- **An alert fires once per condition, and its state is a row.** This slice
  adds two alerts; spec 0009 adds four more on the same mechanism, and spec
  0001's monitoring (ADR 0020) covers heartbeats for jobs rather than
  conditions within them. The rule — a condition that is already reported is
  not reported again, recovery is silent, and the state lives in the database
  rather than in a workflow's memory — outlives this feature and belongs in an
  ADR amending 0020, drafted alongside the first alert here.
