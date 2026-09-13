---
id: 0004
title: Chat queries and the scheduled digest
status: review
created: 2026-09-12
updated: 2026-09-12
owner: admins
supersedes: []
---

# 0004 — Chat queries and the scheduled digest

## Problem

After spec 0003 the household is putting expenses into the books and getting
nothing back. That is the shape of every abandoned ledger: a month of feeding a
system that never answers, and then nobody bothers.

The two failures are separate. Nobody can *ask* anything — "how much on groceries
this month" has no answer short of SQL — and nobody is *told* anything, so the
books are only ever seen by someone who deliberately goes looking, which after
week two is nobody.

## Why

After this slice, the books answer questions in the chat where they were filled
in, and a digest arrives without anyone asking for it. The digest is the more
important half: it is what makes the household notice the books exist.

The measure: a question in plain words gets a number the admins trust, and the
weekly digest is read rather than muted.

## Users and scenarios

- **A member** wants to ask "how much did we spend on food last month" and get a
  number, without learning a query language.
- **A member** wants to know what they personally spent this month.
- **An admin** wants a weekly summary that arrives on its own, short enough to
  read on a phone in ten seconds.
- **An admin** wants a monthly summary with enough substance to act on.
- **An admin** wants to know how much of a figure is still unconfirmed, so they
  know whether to trust it.

## Requirements

### Asking

- **R1.** A member must be able to ask about the books in free text, in Russian or
  English, and receive a figure with the period it covers.
- **R2.** The system must answer at least these, in free text:

  **Spending** — the total for a period; by category; at a merchant; by a member;
  and any of those compared with the previous period.

  **The state of the accounts** — what a named account holds; what the household
  holds in total; **what it owes** in total and per liability; its net position;
  and **how much headroom** is left against an overdraft or credit limit.

  **Movement** — what changed on an account over a period, and what the largest
  expenses in a period were.

- **R2a.** The answerable set is **extended by every later slice that adds a
  view.** A slice that produces a figure for the app without making it askable in
  chat is incomplete: the product is chat-first, so a number reachable only on a
  screen is a regression. Each such slice adds its questions to the mapping and to
  the documented list.
- **R3.** Every answer must state the period it covers and the unconfirmed share
  of the figures in it (ADR 0023).
- **R4.** Every figure must come from a SQL view, never from arithmetic performed
  in a workflow or by the model.
- **R5.** The model must translate a question into a choice among known queries
  and their parameters — never into SQL, and never into a number.
- **R6.** A question the system cannot map to a known query must be refused
  plainly, saying what can be asked instead. It must never guess a figure.
- **R7.** An answer must be a short message, not a table dump, and must respect
  the member's language.
- **R8.** A member must be able to ask about the whole household's books
  (ADR 0016).

### Telling

- **R9.** A weekly digest must be sent to each member on a schedule, in their
  language.
- **R10.** A monthly digest must be sent, covering the closed month.
- **R11.** A digest must contain: the period's total, the largest categories, the
  change against the previous period, and the unconfirmed share. Nothing else.
- **R12.** A digest must contain no commentary, no advice and no judgement about
  the spending (ADR 0022, `agent-persona.md`).
- **R13.** A digest must be generated from the same views that answer questions,
  so a digest and an answer can never disagree.
- **R14.** Each digest must push a heartbeat on success, so a digest that stops
  being sent raises an alert (ADR 0020).
- **R15.** A member must be able to turn their own digests off, and on.
- **R16.** A digest for a period with no data must say so in one line, not be
  suppressed silently.
- **R17.** The weekly digest must be sent on Monday at 09:00 household time and
  the monthly on the 1st, without waiting for reconciliation — it must state the
  period's reconciliation status instead.
- **R18.** Every digest and every answer must include the previous period's
  figure for comparison.
- **R19.** A member must be able to **search** the books in free text — a
  merchant, a note, a fragment of a capture — and receive matching transactions
  with their dates and amounts.
- **R20.** A member must be able to ask **why** a transaction is categorised as it
  is, and be told whether it came from the merchant's default, from an explicit
  choice, or from the model — with the prompt version in the latter case
  (ADRs 0008, 0025).
- **R21.** An admin must be able to **export** a period as CSV — transactions,
  postings and balances — delivered in chat or downloaded from the app. The books
  belong to the household and must be removable from it at any time.
- **R22.** Where a question offers a closed choice — which period, which category
  — the bot must offer it as buttons with a typed equivalent (ADR 0035).
- **R23.** The documented list of answerable questions must be kept current as
  the set grows, because it is the contract: R6 refuses anything outside it, and
  a refusal is only fair if the list is honest.

## Scope

**In scope:** the reporting views, the question-to-query mapping and its prompt,
the answer formatting in both languages, the weekly and monthly digests, their
schedules and heartbeats, and per-member digest preferences.

**Out of scope (and why):**
- Charts and trends over time (spec 0006) — a chart belongs on a screen.
- Forecasts, budgets and "can we afford" questions (spec 0009) — there is nothing
  to forecast from yet.
- Project totals (spec 0010).
- Statement-based reconciliation status beyond the unconfirmed share (spec 0007).
- Free-form analytical questions. The mapped set in R2 is the contract; widening
  it is a later slice, not an open-ended promise.

## Acceptance criteria

- [ ] **A1.** Given a month of captured expenses, when a member asks "how much on
      groceries in October", then the reply states the figure, the period, and the
      unconfirmed share.
- [ ] **A2.** Given the same data, when the equivalent question is asked in
      Russian, then the figure is identical and the reply is in Russian.
- [ ] **A3.** Given a question the system cannot map, when it is asked, then no
      figure is produced and the reply names what can be asked.
- [ ] **A4.** Given any answer, when its figure is compared with the corresponding
      SQL view queried directly, then they are identical.
- [ ] **A5.** Given a question about an account's balance, when it is answered,
      then the figure equals the sum of that account's postings.
- [ ] **A5a.** Given questions about what the household holds, what it owes, its
      net position, and the headroom on a limited account, when each is asked,
      then each is answered from its view — and the headroom answer states the
      limit it is measured against.
- [ ] **A5b.** Given every view that later slices add, when the documented list of
      answerable questions is compared with them, then no view produces a figure
      the app shows and the bot cannot be asked for.
- [ ] **A6.** Given a period containing unconfirmed transactions, when a figure for
      it is reported, then the unconfirmed share is stated and is correct.
- [ ] **A7.** Given the weekly schedule, when it fires, then each member with
      digests enabled receives one, in their own language.
- [ ] **A8.** Given the weekly digest, when it is generated, then its figures match
      the figures the same questions would return.
- [ ] **A9.** Given a member who has turned digests off, when the schedule fires,
      then they receive nothing.
- [ ] **A10.** Given a period with no transactions, when the digest is generated,
      then it is sent and says so in one line.
- [ ] **A11.** Given the digest job is prevented from running, when its heartbeat
      window passes, then an alert reaches the admins.
- [ ] **A12.** Given any digest, when its text is inspected, then it contains no
      advice, no judgement and no accounting vocabulary.
- [ ] **A13.** Given a question, when the model is unavailable, then the failure is
      reported plainly and no figure is invented.
- [ ] **A14.** Given any question, when the model's response is inspected, then it
      contains a query name and parameters and **no number** — every figure in the
      answer came from the database.
- [ ] **A15.** Given a member who is not an admin, when they ask about the whole
      household's spending, then they receive it.
- [ ] **A16.** Given the schedules, when Monday 09:00 household time passes, then
      the weekly digest has been sent; and when the 1st passes, the monthly has —
      without waiting for the month to be reconciled, and stating its
      reconciliation status.
- [ ] **A17.** Given any digest or answer, when it renders, then the previous
      period's figure is present for comparison.
- [ ] **A18.** Given a note stored on a transaction, when a member searches for a
      word in it, then that transaction is returned.
- [ ] **A19.** Given a transaction categorised by the model, when a member asks
      why, then the answer names the model and prompt version; and given one
      categorised from a merchant default, then it says so instead.
- [ ] **A20.** Given a closed month, when an admin exports it, then the CSV's
      totals equal the same period's figures from the views, and it opens in a
      spreadsheet without repair.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A question about a period that predates the opening balances | Answered for the data that exists, with the period's true start stated |
| A question about a category that does not exist | Says so; does not return zero as though the answer were zero |
| A question spanning an open month | Answered, with the period stated as partial |
| A merchant name spelled differently from the registry | Resolved through aliases (ADR 0004); if unresolvable, asks which merchant |
| Two members ask the same question | Same figure, each in their own language |
| A digest period where every record is unconfirmed | Sent, with the share stated as 100% — the figure is still the best available |
| The model maps a question to the wrong query | The answer states the period and query it used, so the mismatch is visible rather than silent |

## Ergonomic cost

- **Who does more work:** nobody. This slice only returns work already done.
- **What queue or obligation it creates:** none. A digest is not an obligation —
  R15 exists so it can never become one.
- **What it interrupts, and how often:** twice a week at most, per member: one
  weekly digest, one monthly. Inside the interruption budget in
  `docs/standards/ergonomics.md`, and deliberately not daily.
- **If nobody touches it for a month:** digests keep arriving and can be ignored;
  a digest that stops arriving raises an alert. Nothing accumulates.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **Latency:** an answer arrives within a few seconds; a digest is background work
  and nobody waits for it.
- **Cost:** one model call per question, for mapping only. A digest costs nothing —
  it is SQL and a template.
- **Data minimisation:** the model receives the question and the list of available
  queries, never the ledger (ADR 0029).

## Open questions

None. Everything this slice needed decided has been decided; what the household
must still supply is listed in spec 0001 and spec 0002.

## Related

- ADRs: 0029, 0004, 0011, 0014, 0017, 0020, 0022, 0023, 0025, 0027
- Specs: 0003 (must be done first), 0006, 0007, 0009, 0010
