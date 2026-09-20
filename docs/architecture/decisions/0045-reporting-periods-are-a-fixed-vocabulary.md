---
id: 0045
title: Reporting periods are a fixed vocabulary resolved in SQL
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0045 - Reporting periods are a fixed vocabulary resolved in SQL

## Context

Every reporting question spec 0004 answers is a question about a period - "this
month", "last month", "this year" - and a period has to mean the same thing to
the bot, to the app (spec 0006), and to the forecast (spec 0009). Two things
turn this into a decision instead of an implementation detail.

First, the model can't invent the dates a period covers. ADR 0029 already keeps
the model out of arithmetic and out of SQL, and asking it to produce `from` and
`to` dates is the same mistake in a different shape, the kind of creativity R5
exists to exclude.

Second, a household has one timezone, set once during setup (spec 0003,
ADR 0034), so "this month" means that timezone's calendar and not a server's or
a browser's. Getting the timezone wrong at the boundary of a month is what makes
a figure quietly wrong for one household and right for another.

## Decision

A period comes from a fixed, named vocabulary - `this_month`, `last_month`,
`month_of:YYYY-MM`, `this_year`, `last_year`, `last_7_days`, `last_30_days` -
and one SQL function, `period_bounds(period, household_tz)`, resolves it to
concrete date bounds. Neither the model nor a workflow resolves a period.

- The model only picks a name from the enum (ADR 0029), and it never produces or
  reasons about a date.
- `period_bounds` also returns the bounds of the previous period, meaning the
  period immediately before the requested one and the same length, so a spend
  view can carry `previous_amount_minor` as a column on the same row (R18)
  instead of costing a second query and a subtraction, which ADR 0040 forbids as
  arithmetic outside the database.
- Every spend view joins against `period_bounds` for every named period at once
  instead of calling a parameterised function per question. A question then
  becomes a `where period = $1` filter, which is what makes the view directly
  queryable and directly testable with no workflow in front of it (ADR 0015).
- A period outside this vocabulary gets a refusal (R6) and not a guess: the
  model names the periods that can be asked about, exactly as it does for an
  unmappable question.
- Widening the vocabulary costs a migration and an enum entry, deliberately,
  which is the same cost R0c already accepts for a new account type.

## Alternatives

| Option | Why rejected |
|---|---|
| Fixed period vocabulary resolved in SQL, carried as a column on every spend view | Chosen; the Decision section gives the reasons |
| Views parameterised by arbitrary `from` and `to` as PostgREST RPC functions | Answers any range, but the model would have to produce dates, which is the creativity R5 excludes, and it moves aggregation into functions while the catalogue calls them views |
| Compute the period-over-period delta in the workflow from two calls | Needs no new columns, and it does arithmetic on money outside the database, which R4 forbids and ADR 0040 calls a defect |
| Let the model write SQL against a read-only role | Answers anything, and no one can review it, nothing bounds it, and R6's refusal path becomes undefinable because no fixed set exists to fall outside of |

## Consequences

Good:
- One question costs one query with one filter, and the previous period comes
  back with it, so nobody forgets a second step.
- The bot, the app, and the forecast share one vocabulary and one way of
  handling the timezone, so "last month" can't mean one thing on a screen and
  another in chat.
- A period the household didn't expect to be asked about gets a clear refusal
  instead of a wrong date computed silently.

Bad, and the price we accept:
- An unusual range such as "the last ten days" is unanswerable until someone
  adds it to the vocabulary. That's a real gap, and R6 makes it visible instead
  of hiding it behind a best-effort date parse.
- Every later slice that reports figures over time inherits this vocabulary, so
  widening it later means a migration that touches every spend view's join
  rather than one local change.

What becomes harder to change later is the names in the vocabulary, once the
bot, the app, and the forecast all refer to them by string. Adding an entry
stays cheap, and renaming one touches three surfaces at once.
