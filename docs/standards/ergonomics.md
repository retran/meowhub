# Ergonomics of the whole system

Not screen design — that is
[ui-design-process.md](ui-design-process.md). This is about the system as
something three people live with for years: what it asks of them, how often, and
what happens when they stop doing it.

The product's real failure mode is not a bug. It is abandonment: the books get
kept for three weeks and then stop, and a ledger with a three-week-old floor is
worth less than none, because nobody trusts a number they cannot date. Every rule
here exists to make abandonment less likely.

## 1. The owner is the bottleneck, and that has to be designed around

Look at what funnels to one person: approving model-derived records (ADR 0023),
every financial correction (ADR 0016), the monthly statement downloads, membership
changes (ADR 0030), overrides on refused imports (ADR 0013), and every alert in
the system (ADR 0020). He also has a job.

Therefore:

- **Nothing may require an admin in real time.** A member's capture must
  complete, and be useful, without him.
- **Every funnel has a drain that does not depend on willpower** — an automatic
  path, an expiry, or an alert saying the process itself is failing.
- **The system must survive two weeks of his absence** with no data loss, no
  blocked members, and no queue that becomes unrecoverable. If a feature cannot
  survive that, it is designed wrong.

## 2. No unbounded queues

Anything that accumulates and needs a human — unconfirmed records, unanswered
clarifying questions, unmatched statement lines, correction requests — must have:

- an **automatic drain** where it is safe (reconciliation confirming records, a
  conservative auto-confirm, an expiry for a stale question), and
- a **ceiling that raises an alert once** when the backlog exceeds it. A queue
  nobody drains is a process failure, not a data state, and it should be reported
  as one.

A queue with neither is a permanent guilty backlog, and everything in it is
eventually rubber-stamped unread — which makes the state meaningless.

## 3. There is one channel, and it has an interruption budget

Everything arrives in Telegram: captures, confirmations, digests, budget
warnings, infrastructure alerts. That is good for attention and fatal if
overspent — a channel people mute is worse than no channel.

The budget, deliberately small:

- **One weekly digest, one monthly.** Not daily.
- **Approvals batched**, at most one prompt a day, and only when something is
  actually waiting.
- **Alerts only when actionable, once per condition.** Never a repeat without new
  information. "Still broken" is not new information.
- **Infrastructure failures go to admins only.** No member is told PostgREST
  restarted.
- **A capture confirmation echoes what was *inferred*, not what was said.** If
  someone wrote the amount and the merchant, repeating them back is noise; the
  category and the account we chose are what they might want to catch.

## 4. Lapses are certain, so the system is forgiving of them

Capture will stop — a busy fortnight, a holiday, illness. When it resumes:

- **The statement import is the safety net.** Backfilling a missed month must be
  one import, not a data-entry session, and it must not produce a mountain of
  duplicates (ADR 0013).
- **No guilt.** The interface never counts the days since anyone last captured,
  never shows a streak, and never asks anyone to catch up. It shows what is known
  and how complete it is.
- **Gaps are visible but not accusatory**: a period reconciled only from
  statements is a fact about the data, shown as such.

## 5. Every member must get something back, early

The admins are motivated; the other two are not, and the daughter least of all. A
member who only ever *feeds* the system stops feeding it.

- **Within the first week, each member sees something that is for them.** For the
  daughter, the only thing she cares about: what she has left.
- **Nobody is told "you may not".** Where a permission blocks someone
  (ADR 0016), the affordance either is absent or turns into asking — and the
  asking is one message, not a form.
- **No member ever needs to understand the accounting**, the confirmation states,
  or the word "reconciliation".

## 5a. The system asks; nobody fills in a form

The household's own facts — which accounts exist, what they hold today, who pays
with what, whether cash is tracked — are **collected by the agent in conversation**,
not gathered in advance into a specification and hard-coded.

This is a design rule, not a nicety:

- A spec that carries the household's balances is stale the day an account is
  opened, and it makes a developer the bottleneck for a fact the household knows.
- A setup screen with twenty fields is the form the product exists to avoid
  (vision principle 1).
- The agent can ask **one question at a time, in the right order, and stop** when
  it has enough to be useful — which is how a person would do it.

So the rule for every slice: if a fact belongs to the household rather than to the
design, the spec says *that the agent must collect it*, and never *what the answer
is*. Setup is a conversation that can be paused and resumed, and a partial answer
leaves a working system with less in it — never a blocked one.

## 6. Count the chores, out loud

The household's real recurring work, and it must stay inside roughly a quarter of
an hour a month or it will not happen:

| Chore | Cadence | Who |
|---|---|---|
| Download and upload three statements (ABN AMRO, ING, ICS) | monthly | owner |
| Review and batch-approve unconfirmed records | weekly, minutes | owner |
| Answer a clarifying question about a capture | occasionally | any member |
| Correct something the model got wrong | occasionally | owner |
| Confirm the restore verification passed | monthly, seconds | owner |

Adding a chore to this table is a cost that belongs in the spec that adds it. If
a slice would add a weekly chore, it should say so and justify it.

## 7. Latency budgets

- **A capture is confirmed within a few seconds.** Someone is standing at a till.
- **The app's first useful paint is fast on mobile data**, and it shows something
  real before everything has loaded.
- **Digests and imports are background work.** Nobody waits for them.
- **A slow model never blocks a capture**: the message is stored and answered
  later (vision principle 6).

## 8. Trust is an ergonomic property

People abandon a ledger they do not believe, and belief is built from small,
boring guarantees:

- Every figure states its **period**.
- Every figure states what it is made of — the **unconfirmed share**, and whether
  a period is reconciled (ADRs 0013, 0023).
- The bot and the app never disagree, because both read the same views.
- Nothing is silently dropped, ever. A message the system could not understand is
  kept and asked about.

## 9. The ergonomic questions every spec answers

Four questions, in the spec, before the work starts. They are in the spec
template for this reason:

1. **Who does more work after this ships, and how much?**
2. **What queue or obligation does it create, and what drains it?**
3. **What does it interrupt, and how often?**
4. **What happens if nobody touches it for a month?**

A slice that cannot answer the fourth is not ready, because a month of nobody
touching it is the normal case, not the exception.
