---
id: 0045
title: Reporting periods are a fixed vocabulary resolved in SQL
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0045 — Reporting periods are a fixed vocabulary resolved in SQL

## Context

Every reporting question spec 0004 answers is a question about a period — "this
month", "last month", "this year" — and the same period concept has to mean the
same thing to the bot, the app (spec 0006) and the forecast (spec 0009). Two
things make this a decision rather than an implementation detail:

- **"For a period" cannot be a date the model invents.** ADR 0029 already keeps
  the model out of arithmetic and out of SQL; asking it to produce `from`/`to`
  dates is the same mistake in a different shape, and it is exactly the kind of
  creativity R5 exists to exclude.
- **A household has one timezone**, set once during setup (spec 0003, ADR 0034),
  and "this month" means that timezone's calendar, not a server's or a browser's.
  Getting this wrong at the boundary of a month is the specific failure mode that
  makes a figure quietly wrong for one household but not another.

## Decision

**A period is chosen from a fixed, named vocabulary — `this_month`, `last_month`,
`month_of:YYYY-MM`, `this_year`, `last_year`, `last_7_days`, `last_30_days` — and
resolved to concrete date bounds by one SQL function,
`period_bounds(period, household_tz)`, never by the model and never in a
workflow.**

- The model's only involvement is picking a name from the enum (ADR 0029); it
  never produces or reasons about a date.
- `period_bounds` also returns the **previous period's own bounds** — the period
  immediately before the requested one, same length — so a spend view can carry
  `previous_amount_minor` as a column on the same row (R18) instead of a second
  query and a subtraction, which ADR 0040 already forbids as arithmetic outside
  the database.
- Every spend view is a fixed join against `period_bounds` for every named
  period at once, not a parameterised function called per question — a question
  is then a `where period = $1` filter, which is what makes the view directly
  queryable and directly testable without a workflow in front of it (ADR 0015).
- A period outside this vocabulary is a refusal (R6), not a guess: the model
  names what periods can be asked about, exactly like an unmappable question.
- The vocabulary widens by a migration and an enum entry, deliberately, the same
  cost R0c already accepts for a new account type.

## Alternatives

| Option | Why rejected |
|---|---|
| Fixed period vocabulary resolved in SQL, carried as a column on every spend view | **chosen** — see Decision |
| Views parameterised by arbitrary `from`/`to` as PostgREST RPC functions | Answers any range, but the model would have to produce dates — exactly the creativity R5 excludes — and it moves aggregation into functions while the catalogue calls them views |
| Compute the period-over-period delta in the workflow from two calls | No new columns needed, but it is arithmetic on money outside the database, which R4 forbids and ADR 0040 calls a defect |
| Let the model write SQL against a read-only role | Answers anything, but it is un-reviewable, unbounded, and makes R6's refusal path undefinable — there is no fixed set to be outside of |

## Consequences

**Good:**
- One question is one query with one filter; the previous period is never
  forgotten because it is not a second step to remember.
- The same vocabulary and the same timezone handling serve the bot, the app and
  the forecast, so "last month" cannot mean something different on a screen than
  in chat.
- A period the household did not expect to be asked about is a clear, honest
  refusal rather than a wrong date silently computed.

**Bad, and the price we accept:**
- An unusual range ("the last ten days") is unanswerable until it is added to
  the vocabulary — a real gap, made visible by R6 rather than hidden by a
  best-effort date parse.
- Every later slice that reports figures over time inherits this vocabulary,
  which means widening it later is a migration touching every spend view's
  join, not a local change.

**What becomes harder to change later:** the vocabulary's own names, once the
bot, the app and the forecast all refer to them by string. Adding an entry is
cheap; renaming one touches three surfaces at once.
