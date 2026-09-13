---
id: 0016
title: Everyone reads the whole ledger; only an admin edits what is already recorded
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0016 — Everyone reads the whole ledger; only an admin edits what is already recorded

## Context

ADR 0030 left per-member visibility as an open product question. ADR 0014 turned
it into a blocking one: authorisation is now row-level security in PostgreSQL, and
policies cannot be written without knowing the answer.

The household is three people who already share the money. The risk being managed
is not privacy between them — it is accidental damage to accumulated books by
someone who did not mean to change anything, and who would not notice they had.

## Decision

- **The household has two admins and one member.** Both parents are admins; the
  daughter is a member. Administrative rights are a role, not a person, so nothing
  in this system depends on one individual being available.
- **Every member reads everything.** One household picture, no per-member
  filtering of the ledger, of reports, or of the app. There are no private
  entries.
- **Every member may capture.** Creating a transaction is not editing.
- **Only an admin may change or delete an already-recorded transaction**, merge
  merchants, confirm or override a reconciliation, or undo an import.
- **Enforced in row-level security**, so the rule holds identically through the
  bot, the app, PostgREST and a psql session — and the negative cases are tested
  by impersonation (ADR 0015).
- **Classification is not a financial fact.** ADR 0021 refines this rule: amount,
  date, account and existence are admin-only, while category and project
  attribution may be changed by any member. Without that split, tagging a
  holiday's spending would fall to the one person not doing most of it.
- **A member who wants a correction asks in chat.** The bot records the request
  against the transaction and notifies the admins, rather than replying "you may
  not". A refusal that leads nowhere would just push people to stop caring about
  accuracy.

## Alternatives

| Option | Why rejected |
|---|---|
| Anyone edits anything | The original assumption. One mistaken tap in the app could silently rewrite months of books, and with three casual users it eventually would |
| Each member edits their own entries | Sounds fair, and weakens reconciliation: a statement-derived correction has no "own" member, so the rule would need an exception immediately. ADR 0023 covers the case that matters — a member may fix their own record while it is still unconfirmed |
| Per-member visibility limits | Contradicts the household picture the product exists to produce, and nobody asked for it |
| Editing allowed but every change reviewed | The audit log already records every change (ADR 0008). A review queue is process where a permission is enough |

## Consequences

**Good:**
- Accumulated books cannot be damaged casually, which is the risk that actually
  exists here.
- One rule, one enforcement point, testable by impersonation.
- Reports and the app need no per-member filtering, so they stay simple.

**Bad, and the price we accept:**
- **This partly collides with vision principle 8** — "a wrong entry must be cheap
  to fix". For the one member who is not an admin, fixing an already-confirmed
  record is asking. ADR 0023 keeps the common case cheap: an unconfirmed record
  can be fixed by whoever captured it.
- The admins are a bottleneck for corrections, in a system whose parser will
  sometimes guess wrong by design. Two of them rather than one is what makes that
  survivable.
- The request-and-notify path is extra machinery that exists only because the
  permission is strict.

**The narrow exception is decided elsewhere.** ADR 0023 gives every transaction a
confirmation state and lets a member edit their own record while it is still
unconfirmed — which covers the "it was 35 not 350" reply without loosening this
rule for the books at large. Whether that window is time-bounded as well is a
blocking question on spec 0003.

**What becomes harder to change later:** loosening this is easy; tightening it
after people are used to editing would not be.
