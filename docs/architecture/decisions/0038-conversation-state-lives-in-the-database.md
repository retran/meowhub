---
id: 0038
title: Conversation state lives in PostgreSQL, never in the workflow engine
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0038 — Conversation state lives in PostgreSQL, never in the workflow engine

## Context

Several things the product promises are **multi-turn**, and none of them can work
without somewhere to remember where the exchange had got to:

- **Setup is a conversation** that asks one question at a time and can be paused
  and resumed, and an admin can ask what still remains (spec 0003).
- **An unparsed capture asks one question** and waits, possibly for days, for the
  answer that completes it.
- **A structural change is restated and waits for agreement** before being
  applied (ADR 0031).
- **"Undo" means the actor's own last action** (ADR 0036), which requires knowing
  what that was.
- **A clarifying question must not be asked twice**, which requires knowing it was
  asked.

The obvious place to keep that is the workflow's own execution context, and it is
the wrong one. n8n's execution history is pruned by design, scoped to executions
rather than to conversations, and disappears entirely if the platform is ever
replaced (ADR 0001). A pending question that vanishes when a container restarts
is worse than no question: the member answered, and nothing happened.

## Decision

**Conversation state is a table in PostgreSQL.** The workflow reads it, writes it,
and holds nothing of its own between messages.

- **One row per exchange in progress**: the member, its kind (setup,
  clarification, structural confirmation, correction request), the step it is on,
  a payload of what has been gathered so far, and when it was opened, last touched
  and closed.
- **A workflow is stateless between messages.** Everything it needs comes from
  that row and from the ledger; nothing is carried in an execution's context, in a
  static workflow variable, or in memory.
- **At most one open conversation per member per kind.** A second setup does not
  start a parallel one; it resumes the first. This is what makes "what still needs
  setting up" answerable.
- **A pending question is idempotent**: asked once, recorded as asked, and never
  re-asked without new information (the ergonomics standard's no-nagging rule).
- **Every exchange expires**, and expiry is visible rather than silent: an
  abandoned setup stays resumable, an unanswered clarification remains listed as
  an unparsed capture, and neither is deleted on a timer (spec 0007's rule against
  self-resolving states).
- **The last action per member is derivable from the audit log** (ADR 0008), not
  from conversation state — so undo works even for something done in the app.
- **Conversation payloads are not the ledger.** Nothing in a payload is a
  financial fact until it becomes a transaction; a half-finished setup holds no
  postings.
- **It is backed up and restored with everything else** (ADR 0009), so a restore
  brings back the half-finished conversation rather than stranding the member
  mid-sentence.

### What this makes testable

Multi-turn flows become scriptable: a test feeds message one, asserts the row, and
feeds message two. That is the only way the setup interview and the
question-and-answer path can be verified at all, and it closes a gap in ADR 0015 —
whose fixtures covered single captures and nothing conversational.

## Alternatives

| Option | Why rejected |
|---|---|
| The workflow engine's execution context | Pruned by design, scoped to an execution, invisible to the app, and lost with the platform. A question that survives only until the next restart is a broken promise |
| A cache (Redis) for conversation state | Right shape, wrong durability: a setup interview spanning days is not cache-shaped, and it adds a component whose loss is silent |
| Reconstructing state from the message history | Telegram has the messages, so it is tempting. It means re-deriving intent from prose on every turn, at model cost, with a different answer each time |
| Keeping it in the app's client | There is no app in the capture path, and the chat is the primary interface |
| One conversation table per kind | More tables, the same shape, and every new conversational feature becomes a migration rather than a row |

## Consequences

**Good:**
- A paused setup, a pending question and a waiting confirmation all survive a
  restart, a redeploy and a restore.
- Multi-turn behaviour becomes testable, which is the only way it will be correct.
- The bot and the app can both see that something is waiting, so a member is not
  the only one who remembers.
- Replacing the orchestrator (ADR 0001's named risk) no longer loses conversations.

**Bad, and the price we accept:**
- Every conversational workflow now starts with a read and ends with a write, so
  there is more plumbing per message and one more thing to get wrong.
- State that outlives a process needs a lifecycle — opened, touched, closed,
  expired — and lifecycles rot when nobody looks at them. The visible-expiry rule
  is what keeps it inspectable.
- Two places describe "what is waiting": conversation rows and unparsed captures.
  They are deliberately separate — one is an exchange, one is a record — and the
  overlap will need care in the app.

**What becomes harder to change later:** the payload's shape, once half-finished
conversations exist in it. Keeping it a document rather than columns is what makes
adding a step cheap.
