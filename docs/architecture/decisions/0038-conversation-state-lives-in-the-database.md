---
id: 0038
title: Conversation state lives in PostgreSQL, never in the workflow engine
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0038 - Conversation state lives in PostgreSQL, never in the workflow engine

## Context

Several things the product promises take more than one message, so the bot needs
somewhere to remember where an exchange had got to:

- Setup is a conversation that asks one question at a time, can be paused and
  resumed, and lets an admin ask what still remains (spec 0003).
- An unparsed capture asks one question and then waits, possibly for days, for
  the answer that completes it.
- A structural change is restated and waits for agreement before it's applied
  (ADR 0031).
- "Undo" means the actor's own last action (ADR 0036), so the bot has to know
  what that action was.
- A clarifying question must not be asked twice, so the bot has to know it was
  already asked.

The obvious place to keep all of that is the workflow's own execution context,
and the owner rejected it because n8n prunes execution history by design, scopes
it to a single execution while a conversation spans many, and loses it entirely
if we ever replace the platform (ADR 0001). A pending question that vanishes when a
container restarts is worse than never asking: the member answers, and nothing
happens.

## Decision

Conversation state is a table in PostgreSQL. The workflow reads it, writes it,
and holds nothing of its own between messages.

- The table keeps one row per exchange in progress: the member, its kind (setup,
  clarification, structural confirmation, correction request), the step it's on,
  a payload of what the bot has gathered so far, and when the exchange was
  opened, last touched, and closed.
- A workflow keeps no state between messages. Everything it needs comes from
  that row and from the ledger, so nothing rides in an execution's context, in a
  static workflow variable, or in memory.
- A member has at most one open conversation per kind. A second setup resumes
  the first instead of starting a parallel one, which is what makes "what still
  needs setting up" answerable.
- A pending question is idempotent: the bot asks it once, records that it asked,
  and re-asks only when new information arrives (the ergonomics standard's
  no-nagging rule).
- Every exchange expires, and expiry is visible. An abandoned setup stays
  resumable, an unanswered clarification stays listed as an unparsed capture,
  and a timer deletes neither of them (spec 0007's rule against self-resolving
  states).
- The last action per member comes from the audit log (ADR 0008), which records
  what the member did in the app as well, so undo works there too.
- A conversation payload isn't the ledger. Nothing in a payload is a financial
  fact until it becomes a transaction, so a half-finished setup holds no
  postings.
- The table is backed up and restored with everything else (ADR 0009), so after
  a restore the member can carry on a half-finished conversation from the step
  it had reached.

### What this makes testable

Keeping the state in a table makes multi-turn flows scriptable: a test feeds
message one, asserts the row, and feeds message two. That's the only way to
verify the setup interview and the question-and-answer path, and it closes a gap
in ADR 0015, whose fixtures covered single captures and nothing conversational.

## Alternatives

| Option | Why rejected |
|---|---|
| The workflow engine's execution context | Pruned by design, scoped to an execution, invisible to the app, and lost with the platform; a question that survives only until the next restart is a broken promise |
| A cache (Redis) for conversation state | Right shape, wrong durability: a setup interview that spans days isn't cache-shaped, and Redis adds a component whose loss is silent |
| Reconstructing state from the message history | Tempting because Telegram already has the messages, but it re-derives intent from prose on every turn, at model cost, with a different answer each time |
| Keeping it in the app's client | No app takes part in the capture path, and the chat is the primary interface |
| One conversation table per kind | More tables with the same shape, and every new conversational feature would cost a migration instead of a row |

## Consequences

Good:
- A paused setup, a pending question, and a waiting confirmation all survive a
  restart, a redeploy, and a restore.
- Multi-turn behaviour becomes testable, which is the only way it will be
  correct.
- Both the bot and the app can see that something is waiting, so the member
  isn't the only one who remembers.
- Replacing the orchestrator, which ADR 0001 names as a risk, no longer loses
  conversations.

Bad, and the price we accept:
- Every conversational workflow now starts with a read and ends with a write, so
  each message carries more plumbing and one more thing to get wrong.
- State that outlives a process needs a lifecycle - opened, touched, closed,
  expired - and lifecycles rot when nobody looks at them, which is why expiry
  has to stay visible.
- Two places describe what's waiting: conversation rows and unparsed captures.
  We keep them separate because one is an exchange and one is a record, and the
  app will need care where they overlap.

The payload's shape gets harder to change once half-finished conversations are
stored in it, so we keep the payload as a document. Adding a step to an
interview then costs no migration.
