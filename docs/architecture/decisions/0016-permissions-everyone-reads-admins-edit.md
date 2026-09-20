---
id: 0016
title: Everyone reads the whole ledger; only an admin edits what is already recorded
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0016 - Everyone reads the whole ledger; only an admin edits what is already recorded

## Context

ADR 0030 left per-member visibility as an open product question, and ADR 0014
turned it into a blocking one: authorisation is now row-level security in
PostgreSQL, and we can't write the policies without knowing the answer.

The household is three people who already share the money, so we aren't managing
privacy between them. What we're managing is accidental damage to accumulated
books by someone who didn't mean to change anything and wouldn't notice they
had.

## Decision

- The household has two admins and one member: both parents are admins and the
  daughter is a member. Administrative rights are a role and not a person, so
  nothing here depends on one individual being available.
- Every member reads everything. There is one household picture, with no
  per-member filtering of the ledger, the reports or the app, and no private
  entries.
- Every member can capture, because creating a transaction isn't editing one.
- Only an admin can change or delete an already-recorded transaction, merge
  merchants, confirm or override a reconciliation, or undo an import.
- Row-level security enforces the rule, so it holds identically through the bot,
  the app, PostgREST and a psql session, and we test the negative cases by
  impersonation (ADR 0015).
- Classification is not a financial fact, so ADR 0021 refines the rule: amount,
  date, account and existence are admin-only, while any member can change a
  category or a project attribution. Without that split, tagging a holiday's
  spending would fall to the one person who isn't doing most of it.
- A member who wants a correction asks in chat, and the bot records the request
  against the transaction and notifies the admins instead of replying "you may
  not". A refusal that leads nowhere would teach people to stop caring about
  accuracy.

## Alternatives

| Option | Why rejected |
|---|---|
| Anyone edits anything | The original assumption. One mistaken tap in the app could silently rewrite months of books, and with three casual users it eventually would |
| Each member edits their own entries | Sounds fair, but it weakens reconciliation, because a statement-derived correction has no "own" member and the rule would need an exception at once. ADR 0023 covers the case that matters: a member can fix their own record while it is still unconfirmed |
| Per-member visibility limits | Contradicts the household picture the product exists to produce, and nobody asked for it |
| Editing allowed but every change reviewed | The audit log already records every change (ADR 0008), so a review queue would add process where a permission does the job |

## Consequences

**Good:**
- Nobody can damage the accumulated books casually, which is the risk that
  actually exists here.
- One rule with one enforcement point, which we can test by impersonation.
- Reports and the app need no per-member filtering, so they stay simple.

**Bad, and the price we accept:**
- The rule partly collides with vision principle 8, "a wrong entry must be cheap
  to fix", because the one member who isn't an admin has to ask before an
  already-confirmed record changes. ADR 0023 keeps the common case cheap by
  letting whoever captured a record fix it while it is unconfirmed.
- The admins become a bottleneck for corrections in a system whose parser will
  sometimes guess wrong by design. Having two admins rather than one is what
  makes that survivable.
- The request-and-notify path is extra machinery that exists only because the
  permission is strict.

ADR 0023 decides the narrow exception. It gives every transaction a confirmation
state and lets a member edit their own record while it is still unconfirmed,
which covers the "it was 35 not 350" reply without loosening this rule for the
books at large. Whether that window is also time-bounded is a blocking question
on spec 0003.

**What becomes harder to change later:** loosening this rule is easy, while
tightening it once people are used to editing would not be.
