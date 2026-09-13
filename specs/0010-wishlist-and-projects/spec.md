---
id: 0010
title: The wishlist and projects
status: approved
created: 2026-09-12
updated: 2026-09-13
owner: admins
supersedes: []
---

# 0010 — The wishlist and projects

## Problem

Two things the household wants to keep track of, and neither fits anything built
so far.

**Wants with no date.** A new bike, a better mattress, a weekend somewhere. They
are not commitments and not planned purchases, because nobody has decided when —
and today they live in someone's head or in a note, which means they are forgotten
or bought impulsively.

**Money with a name and a span.** A holiday is flights, hotels, restaurants and a
car hire, spread across four categories and two months. Buying a house is a
deposit, a notary, transfer tax and a van, spread across a year. Neither can be
answered by a category, which says *what kind* of expense; nor by a budget, which
is per category per period while a project's target is a lifetime total; nor by a
planned purchase, which is one transaction.

So two questions have no answer: "what did the holiday actually cost" and "can we
have the deposit by March".

## Why

After this slice, wants are written down without pretending to be plans, and a
project can be answered for — both forwards, does it fit, and backwards, what did
it cost.

The measure: a holiday's total is available afterwards without anyone
reconstructing it from a bank statement, and a large purchase is decided against a
projection rather than a feeling.

## Users and scenarios

- **A member** wants to add something to a wishlist in one message, with no
  ceremony and no date.
- **An admin** wants to turn a wish into a plan by giving it a date, and see the
  effect on the forecast.
- **A member** wants their holiday spending counted towards the holiday as they
  spend it.
- **An admin** wants to know what a project has cost so far against its target.
- **An admin** wants to know what would have to be set aside per month to reach a
  target by a date.
- **A member** wants to see the wishlist ordered by what the household could
  actually afford next.

## Requirements

### Wishes

- **R1.** A member must be able to add a wish in chat or the app: a name, an
  estimated amount, an optional priority. No date.
- **R2.** A wish must be outside the forecast entirely until it has a target date.
- **R3.** Giving a wish a target date must promote it to a planned purchase
  (ADR 0012), which is the only difference between them.
- **R4.** A wish must be able to belong to a project.
- **R5.** A fulfilled wish must be linked to the transaction that fulfilled it,
  never converted into one.
- **R6.** A wish must be droppable, and dropped wishes must stay visible in a
  closed list rather than vanishing.

### Projects

- **R7.** An admin must be able to create a project with a name, a state, an
  optional target date or range, and an optional target amount. States: `idea`,
  `planning`, `active`, `done`, `abandoned`.
- **R8.** A transaction must be able to belong to one project, orthogonally to its
  category (ADR 0021).
- **R9.** Any member must be able to set or change a transaction's project — it is
  classification, not a financial fact (ADRs 0016, 0021).
- **R10.** A project report must show spend to date against its target, broken
  down by category and by period.
- **R11.** A project must be able to hold wishes and planned purchases, and its
  report must distinguish spent, planned and merely wished.
- **R12.** For a project with a target amount and date, the forecast must answer
  whether it fits, and what would need setting aside per month to reach it.
- **R13.** No project may hold money or move it between accounts. Its target is an
  expectation (ADR 0012).
- **R14.** When an active project has a date range, the bot should ask whether a
  capture inside that range belongs to it — as a question, never as an assumption.
- **R14a.** That question must be asked only for captures above a configurable
  amount, defaulting to 25 €.
- **R14b.** Feasibility must be computed from known commitments only, and must say
  so.

### Together

- **R15.** The wishlist must be presentable ordered by affordability, using the
  forecast from spec 0009.
- **R16.** Every project and forecast figure must come from a SQL view, shared by
  the bot and the app.
- **R16a.** Every figure in this slice must be **askable in chat**: what a project
  has cost so far, how that stands against its target, whether it fits by its
  date, what would need setting aside monthly, and what is on the wishlist in
  order of affordability (spec 0004, R2a).
- **R17.** Project and wishlist figures must state what they include — spent,
  planned, wished — because mixing them is the obvious way to mislead.
- **R18.** Any member may add a wish, and every wish is visible to every member.

## Scope

**In scope:** wishes and their promotion to planned purchases, projects with
states and targets, transaction-to-project attribution in chat and the app, the
project report, the feasibility and set-aside calculation, affordability ordering,
and the prompt for the belongs-to-a-project question.

**Out of scope (and why):**
- Splitting one transaction across two projects (ADR 0021's known limit). It needs
  transaction splitting, which no slice has yet.
- Reserving or earmarking money in real accounts — envelope budgeting, rejected in
  ADR 0012.
- Shared or collaborative wishlists with people outside the household.
- Price tracking, links to shops, or images for wishes. A wish is a name and an
  amount.
- Project task tracking. A project here is money with a name and a target; chores
  and deadlines are a different product (ADR 0021).

## Acceptance criteria

- [ ] **A1.** Given a member adding a wish with no date, when the forecast is read,
      then it is unchanged — an undated want does not affect any projection.
- [ ] **A2.** Given that wish given a target date, when the forecast is read, then
      it appears as a planned purchase on that date.
- [ ] **A3.** Given a wish fulfilled by a purchase, when it is closed, then it links
      to that transaction and no new transaction is created.
- [ ] **A4.** Given a project and transactions across three categories and two
      months attributed to it, when its report is read, then the total equals the
      sum of those transactions, broken down by both category and month.
- [ ] **A5.** Given the same transactions, when the category report is read, then
      each still appears under its own category — project attribution changes no
      category figure.
- [ ] **A6.** Given a member who is not an admin, when they attribute their own
      spending to a project, then it succeeds; and when they change an amount, it
      fails.
- [ ] **A7.** Given a project with a target of 3 000 € by March and current
      balances and commitments, when feasibility is read, then it states whether it
      fits and the monthly amount required, and states what it assumed.
- [ ] **A8.** Given a project with no target amount, when its report is read, then
      spend to date is shown and no feasibility is claimed.
- [ ] **A9.** Given an active project with a date range and a capture inside it,
      when the capture is confirmed, then the member was asked whether it belongs
      to the project and the answer was honoured — the project was never set
      without asking.
- [ ] **A10.** Given a project report containing spent, planned and wished amounts,
      when it renders, then the three are separated and labelled, in the app and in
      chat alike.
- [ ] **A11.** Given the wishlist ordered by affordability, when it renders, then
      the ordering follows the forecast and the assumption is stated.
- [ ] **A12.** Given a project marked done, when its report is read, then it is
      final and still available — a finished holiday keeps its total.
- [ ] **A13.** Given every figure in this slice, when compared between the bot and
      the app, then they are identical.
- [ ] **A14.** Given a project with a target amount and spending attributed to it,
      when the ledger is inspected, then no account exists for the project and no
      posting was created by it — a project groups transactions and holds no money
      (ADRs 0012, 0021).
- [ ] **A15.** Given a wish added by the member who is not an admin, when any other
      member reads the wishlist, then they see it.
- [ ] **A16.** Given a project with spending and a target, when its cost, its
      standing against the target and its feasibility are each asked for in chat,
      then each is answered and matches the app.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A project with no transactions yet | Report shows zero spent against its target, not an empty state |
| A transaction attributed to a project, then re-attributed | Allowed; the audit record keeps both |
| A shop trip mixing holiday and household items | Cannot be split (known limit); the member chooses one project or none, and the limitation is stated rather than hidden |
| A wish more expensive than any projected balance | Kept, ordered last, and never presented as impossible — only as not yet affordable |
| A project spanning a year boundary | Reports by its own range, not by calendar year |
| An abandoned project with spending already attributed | The spending stays in the books and in the project's final total |
| Two projects with overlapping date ranges | The belongs-to question offers both; it never guesses |
| A wish with no estimated amount | Allowed; it is excluded from affordability ordering and says why |

## Ergonomic cost

- **Who does more work:** whoever wants the answer. Adding a wish is one message.
  Attributing spending is a tap, and it is the only ongoing cost — a project's
  total is only as good as people's discipline on holiday, which the
  belongs-to-a-project question exists to reduce.
- **What queue or obligation it creates:** none. Wishes are not obligations, and
  R6 means nothing has to be tidied. Unattributed spending is not a backlog; it is
  simply spending.
- **What it interrupts, and how often:** one question per capture, only while a
  project is active with a date range covering today. Outside those windows,
  nothing.
- **If nobody touches it for a month:** wishes sit there; a project's total is
  whatever was attributed. Nothing degrades, and nothing nags.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **No model in the numbers.** The model asks the belongs-to question; the totals
  are SQL.
- **The belongs-to question is asked at most once per capture**, and never twice
  for the same one.
- **Feasibility never states certainty it does not have**: every projection names
  its assumptions (spec 0009, R16).

## Open questions

None. Everything this slice needed decided has been decided; what the household
must still supply is listed in spec 0001 and spec 0002.

## Related

- ADRs: 0011, 0012, 0016, 0021, 0022
- Specs: 0009 (must be done first), 0006 (carries the screens)
