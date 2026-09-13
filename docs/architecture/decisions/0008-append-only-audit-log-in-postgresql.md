---
id: 0008
title: Append-only audit log in PostgreSQL, enforced by triggers
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0008 — Append-only audit log in PostgreSQL, enforced by triggers

## Context

The ledger is shared by three people and written by an AI that guesses. That
combination makes "who changed this, when, and what did it say before" a routine
question, not a forensic one: an amount that looks wrong needs a history before
anyone argues about it.

Three things make a bolt-on log inadequate:

- **There is more than one writer.** n8n writes captures, statement imports
  rewrite entries in bulk (vision principle 8), and ADR 0007 admits NocoDB as a
  second writer for repairs. A log maintained by the workflows would miss
  everything the grid does.
- **Model decisions need to be reconstructable.** When a parse is wrong, the
  useful question is which model saw which input and returned what — ADR 0029
  records the model id per entry, but not the exchange.
- **Deletion must leave a trace.** Otherwise a mistake and a cover-up are
  indistinguishable, which is precisely what an audit log exists to prevent.

n8n's own execution history is not a substitute: it is pruned, it is scoped to
executions rather than to data, and it disappears if the platform is replaced.

## Decision

A complete, **append-only audit log lives in PostgreSQL** alongside the data it
describes, and is written by **database triggers** rather than by workflows — so
no writer, present or future, can bypass it.

- **Every state change on every domain table** produces an audit row: the table,
  the row id, the operation, the full before and after images, the actor, and the
  timestamp. Deletes are recorded with their final state.
- **The actor is always recorded** and never null: which household member, or
  which automated process (a statement import, a scheduled job, a repair in the
  grid). Workflows pass the acting member into the transaction; the trigger reads
  it from there.
- **Every inbound message and every model exchange is logged**: the raw Telegram
  message, the prompt, the model id, the response, latency and cost. This is what
  makes a wrong parse explainable, and what ADR 0004's unparsed captures are
  recovered from.
- **The log is immutable.** No workflow, and no application role, may update or
  delete audit rows; only an admin's administrative role can, and only for
  retention pruning.
- **Retention is indefinite by default.** The data is small and its value is
  precisely its age. Message and model payloads may be pruned on a schedule if
  they grow, but domain-change rows are kept.
- **Audit rows are part of the backup set** (ADR 0002) and restoring them is
  tested with the rest.

Privacy is the counterweight to completeness: the log holds receipt images and
statement contents, so it is an admin surface with the same protection as the
others (ADR 0032), never exposed through the bot.

## Alternatives

| Option | Why rejected |
|---|---|
| Logging from inside n8n workflows | Misses every write that does not go through a workflow — statement imports done by hand, repairs in the grid, direct SQL. An audit log with known gaps is worse than none, because it invites false confidence |
| Relying on n8n execution history | Pruned by design, scoped to executions not to rows, and lost when the platform changes. It answers "did the workflow run", not "what happened to this expense" |
| A dedicated audit service or log shipper (Loki, an SIEM) | Right answer at company scale, disproportionate for one household. It also separates the log from the data, so a restore can produce a ledger and an audit trail that disagree |
| Soft deletes and `updated_at` columns only | Records that something changed, not what it was or who did it. Insufficient for the argument the log exists to settle |
| Event sourcing as the primary model | Gives a perfect history, and makes every ordinary query harder for the rest of the project's life. Too high a price for a household ledger |

## Consequences

**Good:**
- Every change is attributable and reversible, whichever writer made it.
- A wrong AI parse can be traced to the exact input and response, which is how
  prompts actually get improved.
- Bulk statement reconciliation becomes safe to run: its effects are fully
  visible afterwards.

**Bad, and the price we accept:**
- Storage grows with every change, and model payloads are the bulk of it. The
  pruning policy above is the release valve.
- Triggers are code in the database: they must be migrated and reviewed like any
  other schema change, and a bug there affects every write.
- Passing the acting member into every transaction is a discipline the workflows
  have to keep; a missing actor has to fail loudly rather than default to
  "system".
- The log concentrates sensitive data — receipts, statements, full history — in
  one place, raising the cost of a breach.

**What becomes harder to change later:**
- The audit row shape, once years of history exist in it. It is therefore
  deliberately generic (table, row, before, after, actor) rather than modelled
  per domain table.
