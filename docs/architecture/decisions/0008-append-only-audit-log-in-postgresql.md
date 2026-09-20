---
id: 0008
title: Append-only audit log in PostgreSQL, enforced by triggers
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0008 - Append-only audit log in PostgreSQL, enforced by triggers

## Context

Three people share the ledger and an AI that guesses writes to it, which makes
"who changed this, when, and what did it say before" a routine question rather
than a forensic one: an amount that looks wrong needs a history before anyone
argues about it.

A log bolted on afterwards would not answer that question, for three reasons:

- More than one writer touches the data. n8n writes captures, statement imports
  rewrite entries in bulk (vision principle 8), and ADR 0007 admits NocoDB as a
  second writer for repairs. A log kept by the workflows would miss everything
  the grid does.
- We have to be able to reconstruct a model's decision. When a parse is wrong,
  the useful question is which model saw which input and returned what, and
  ADR 0029 records the model id per entry but not the exchange.
- A delete has to leave a trace, because otherwise a mistake and a cover-up look
  the same, which is exactly what an audit log exists to prevent.

n8n's own execution history is no substitute: it gets pruned, it covers
executions instead of data, and it disappears with the platform if we replace
it.

## Decision

A complete, **append-only audit log lives in PostgreSQL** next to the data it
describes, written by database triggers instead of by workflows, so no writer we
have now or add later can bypass it. Six rules define it:

- Every state change on every domain table produces an audit row holding the
  table, the row id, the operation, the full before and after images, the actor
  and the timestamp. A delete is recorded with its final state.
- The actor is always recorded and never null, naming either the household
  member or the automated process: a statement import, a scheduled job, or a
  repair in the grid. Workflows pass the acting member into the transaction and
  the trigger reads it from there.
- Every inbound message and every model exchange is logged: the raw Telegram
  message, the prompt, the model id, the response, latency and cost. That is
  what makes a wrong parse explainable, and what we recover ADR 0004's unparsed
  captures from.
- The log is immutable, so no workflow and no application role can update or
  delete audit rows. Only an admin's administrative role can, and only to prune
  for retention.
- We keep audit rows indefinitely by default, because the data is small and its
  value is its age. Message and model payloads can be pruned on a schedule if
  they grow, and domain-change rows stay.
- Audit rows are part of the backup set (ADR 0002), and we test restoring them
  with the rest.

Privacy is the counterweight to a complete log: it holds receipt images and
statement contents, so we treat it as an admin surface with the same protection
as the others (ADR 0032) and never expose it through the bot.

## Alternatives

| Option | Why rejected |
|---|---|
| Logging from inside n8n workflows | Misses every write that goes around a workflow: statement imports done by hand, repairs in the grid, direct SQL. An audit log with known gaps is worse than none, because it invites false confidence |
| Relying on n8n execution history | Pruned by design, scoped to executions instead of rows, and lost when the platform changes. It answers whether the workflow ran, not what happened to this expense |
| A dedicated audit service or log shipper (Loki, an SIEM) | The right answer at company scale and far too much for one household. It also separates the log from the data, so a restore can produce a ledger and an audit trail that disagree |
| Soft deletes and `updated_at` columns only | Records that something changed, and neither what it was nor who did it, so it cannot settle the argument the log exists for |
| Event sourcing as the primary model | Gives a perfect history and makes every ordinary query harder for the rest of the project's life. Too high a price for a household ledger |

## Consequences

We gain three things:

- Every change is attributable and reversible, whichever writer made it.
- We can trace a wrong AI parse to the exact input and response, which is how
  prompts actually get better.
- Running bulk statement reconciliation becomes safe, because its effects are
  fully visible afterwards.

We accept four costs in return:

- Storage grows with every change, and model payloads are most of it. Pruning,
  as the decision above describes it, is the release valve.
- Triggers are code in the database, so we migrate and review them like any
  other schema change, and a bug in one affects every write.
- Passing the acting member into every transaction is a discipline the workflows
  have to keep, and a missing actor has to fail loudly instead of defaulting to
  "system".
- The log gathers receipts, statements and the full history in one place, which
  raises what a breach would cost.

The audit row shape is what gets harder to change, once years of history sit in
it, so we keep it generic - table, row, before, after, actor - instead of
modelling it per domain table.
