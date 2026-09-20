# Ergonomics of the whole system

This document is about the system as something three people live with for years:
what it asks of them, how often, and what happens when they stop doing it. Screen
design is a separate subject, covered in
[ui-design-process.md](ui-design-process.md).

The product's real failure mode is not a bug but abandonment: the household keeps
the books for three weeks and then stops, and a ledger whose floor is three weeks
old is worth less than no ledger at all, because nobody trusts a number they
can't date. Every rule below exists to make abandonment less likely.

## 1. The owner is the bottleneck, and that has to be designed around

A lot funnels to one person: approving model-derived records (ADR 0023), every
financial correction (ADR 0016), the monthly statement downloads, membership
changes (ADR 0030), overrides on refused imports (ADR 0013), and every alert in
the system (ADR 0020). He also has a job, so three rules follow.

- No part of the system requires an admin in real time. A member's capture
  completes, and is useful, without him.
- Every funnel has a drain that doesn't depend on willpower: an automatic path,
  an expiry, or an alert that says the process itself is failing.
- The system survives two weeks of his absence with no data loss, no blocked
  members, and no queue that becomes unrecoverable. A feature that can't survive
  that is designed wrong.

## 2. No unbounded queues

Several things accumulate and then need a human: unconfirmed records, unanswered
clarifying questions, unmatched statement lines, and correction requests. Each of
them needs two mechanisms, and a queue that has neither becomes a permanent
guilty backlog whose contents are eventually rubber-stamped unread, which makes
the state meaningless.

- An automatic drain wherever draining is safe: reconciliation that confirms
  records, a conservative auto-confirm, or an expiry for a stale question.
- A ceiling that raises an alert once when the backlog exceeds it, because a
  queue nobody drains is a failure of the process and not a state of the data,
  and we report it as one.

## 3. There is one channel, and it has an interruption budget

Everything arrives in Telegram: captures, confirmations, digests, budget
warnings, and infrastructure alerts. One channel is good for attention, and
overspending it is fatal, because people mute a channel that interrupts them too
often and a muted channel is worse than no channel. The budget below is
deliberately small.

- One weekly digest and one monthly digest. Not daily.
- Approvals batched into at most one prompt a day, and only when something is
  actually waiting.
- Alerts only when a person can act on them, once per condition, and never a
  repeat without new information. "Still broken" is not new information.
- Infrastructure failures to admins only. No member is told that PostgREST
  restarted.
- A capture confirmation echoes what the agent *inferred* and not what the member
  said. If someone wrote the amount and the merchant, repeating those back is
  noise; the category and the account we chose are what they might want to catch.

## 4. Lapses are certain, so the system is forgiving of them

Capture will stop for a busy fortnight, a holiday, or an illness. Three rules
decide what the household finds when it resumes.

- The statement import is the safety net. Backfilling a missed month takes one
  import rather than a data-entry session, and it must not produce a mountain of
  duplicates (ADR 0013).
- No guilt. The interface never counts the days since anyone last captured, never
  shows a streak, and never asks anyone to catch up. It shows what is known and
  how complete it is.
- Gaps are visible without being accusatory: a period reconciled only from
  statements is a fact about the data, and we show it as one.

## 5. Every member must get something back, early

The admins are motivated, the other two are not, and the daughter least of all. A
member who only ever *feeds* the system stops feeding it, so each member has to
get something out of it early.

- Within the first week, each member sees something that is for them. For the
  daughter that is the only thing she cares about: what she has left.
- Nobody is told "you may not". Where a permission blocks someone (ADR 0016), the
  control is either absent or turns into asking, and the asking is one message
  rather than a form.
- No member ever needs to understand the accounting, the confirmation states, or
  the word "reconciliation".

## 5a. The system asks; nobody fills in a form

The agent collects the household's own facts in conversation - which accounts
exist, what they hold today, who pays with what, and whether cash is tracked -
instead of anyone gathering them in advance into a specification and hard-coding
them. This is a design rule and not a nicety, for three reasons.

- A spec that carries the household's balances is stale the day an account is
  opened, and it makes a developer the bottleneck for a fact the household
  already knows.
- A setup screen with twenty fields is the form the product exists to avoid
  (vision principle 1).
- The agent can ask one question at a time, in the right order, and stop when it
  has enough to be useful, which is how a person would do it.

Every slice follows from that: when a fact belongs to the household rather than
to the design, the spec says *that the agent must collect it* and never *what the
answer is*. Setup is a conversation anyone can pause and resume, so a partial
answer leaves a working system with less in it and never a blocked one.

## 6. Count the chores, out loud

The table below is the household's real recurring work. It has to stay inside
roughly a quarter of an hour a month, or the household won't do it.

| Chore | Cadence | Who |
|---|---|---|
| Download and upload three statements (ABN AMRO, ING, ICS) | monthly | owner |
| Review and batch-approve unconfirmed records | weekly, minutes | owner |
| Answer a clarifying question about a capture | occasionally | any member |
| Correct something the model got wrong | occasionally | owner |
| Confirm the restore verification passed | monthly, seconds | owner |

Adding a chore to this table is a cost, and it belongs in the spec that adds it.
A slice that would add a weekly chore says so and justifies it.

## 7. Latency budgets

Four budgets matter for how the system feels; [budgets.md](budgets.md) gives the
numbers behind them.

- A capture is confirmed within a few seconds, because someone is standing at a
  till.
- The app's first useful paint is fast on mobile data, and it shows something
  real before everything has loaded.
- Digests and imports are background work, and nobody waits for them.
- A slow model never blocks a capture: the agent stores the message and answers
  it later (vision principle 6).

## 8. Trust is an ergonomic property

People abandon a ledger they don't believe, and they build belief out of small,
boring guarantees.

- Every figure states its period.
- Every figure states what it is made of: the unconfirmed share, and whether the
  period is reconciled (ADRs 0013, 0023).
- The bot and the app never disagree, because both read the same views.
- Nothing is silently dropped, ever. The system keeps a message it couldn't
  understand and asks about it.

## 9. The ergonomic questions every spec answers

Every spec answers these four questions before the work starts, which is why they
are in the spec template.

1. Who does more work after this ships, and how much?
2. What queue or obligation does it create, and what drains it?
3. What does it interrupt, and how often?
4. What happens if nobody touches it for a month?

A slice that can't answer the fourth question isn't ready, because a month of
nobody touching it is the normal case and not the exception.
