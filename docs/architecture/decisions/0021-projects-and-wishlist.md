---
id: 0021
title: Projects are a second reporting axis; the wishlist is what has no date yet
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0021 - Projects are a second reporting axis; the wishlist is what has no date yet

## Context

ADR 0012 models what the household intends to spend: budgets per category per
period, recurring commitments, and planned purchases on a date. The owner then
asked for two things that don't fit any of those shapes.

The first is a wishlist: things the household wants, with no date and no
commitment. A planned purchase already has a target date, and a wish is what
exists before anyone decides when.

The second is projects, such as a holiday or buying a house. A project isn't a
purchase. A holiday is flights, hotels, restaurants and a car hire, spread
across four categories and two months. Buying a house is a deposit, a notary,
transfer tax, a mortgage arrangement fee and a van, spread across a year. The
existing model can't express either:

- A category answers what kind of expense something is, and a holiday spans
  several categories.
- A budget is per category and per period, while a project's budget is a
  lifetime total that ignores month boundaries.
- A planned purchase is one transaction, while a project is many, and most of
  them nobody can foresee one by one.

A project is therefore a different kind of thing: a grouping of real
transactions across categories and time, with a target.

## Decision

### Projects are a second reporting axis on the ledger

- A project has a name, a state, an optional target date or date range, and an
  optional target amount. The states are `idea`, `planning`, `active`, `done`
  and `abandoned`.
- A transaction can belong to one project. That reference is a dimension on the
  transaction and sits beside its category, so a restaurant during the holiday
  is still `Expenses:Dining` and is also part of `Holiday 2027`.
- Reporting gains a second axis: spend-to-date per project against its target,
  across every category and period the project touches, next to the existing
  per-category per-period reports. Both are SQL views (ADRs 0004, 0014), so the
  bot and the app give the same answer.
- Projects are not postings and hold no money. As in ADR 0012, a project's
  target is an expectation, and the ledger records only what happened.

### Saving up is shown, never simulated

For a project with a target amount and date, the forecast answers two questions:
whether the project fits, by comparing the projected balances from ADR 0012
against the target, and what the household would need to set aside per month to
reach it.

The forecast moves no money between accounts and reserves none. Doing so would
be envelope budgeting, which ADR 0012 rejected, and it would make a balance mean
something other than what the bank says.

### The wishlist is the state before a date

- A wish is an item with a name, an estimated amount, an optional priority and
  no date. It stays out of the forecast, because an undated want is not a
  commitment.
- Giving a wish a target date promotes it to a planned purchase (ADR 0012), and
  it then enters the forecast. That promotion is the only difference between the
  two, and we made it one step on purpose.
- A wish or a planned purchase can belong to a project, so a holiday can carry
  its intended flights and its vague "maybe a day trip" at the same time.
- When a wish is fulfilled we link it to the transaction that fulfilled it, and
  never convert it into one.

### Attribution is classification, not a financial fact

Tagging a transaction to a project, like setting its category, changes no
amount, no account and no date. It is classification, so any member can do it
and tag their own holiday spending as it happens.

This refines ADR 0016, which reserves editing recorded transactions to the
owner. We draw the line at financial facts: amount, date, account and existence
are owner-only, while category and project are open to any member. Without that
split the feature doesn't work, because only one person could tag a holiday, and
it wouldn't be the person doing most of the spending.

## Alternatives

| Option | Why rejected |
|---|---|
| A project as a category, or a category subtree | Loses the real category of each expense, so a holiday dinner stops being dining, and it can't express a lifetime budget across periods |
| Free-text tags on transactions | Would cover projects and everything else, and would decay at once into three spellings of one holiday, with no target, no state and no report |
| A project as a separate ledger or set of accounts | Buys double-entry purity at the cost of usability: transfers in and out of a "holiday account" that exists at no bank, and balances that no longer match the statements |
| Reserving money for a project in a real sub-account | Envelope budgeting under another name, already rejected in ADR 0012, and it makes account balances disagree with the bank |
| Wishes and planned purchases as one thing with a nullable date | Close to what we chose. The difference is that a dated item enters the forecast and an undated one must not, so one table with an explicit state is fine while one concept would blur that line |
| A general project management module - tasks, deadlines, checklists | The vision's "not a general household planner" still holds. A project here is money with a name and a target, not work to be tracked |

## Consequences

**Good:**
- The household can answer "what did the holiday actually cost" and "can we
  afford the house deposit by March", which is the point of running a household
  like a firm.
- A wish costs nothing to write down and stays out of the forecast until
  somebody commits to a date.
- One extra dimension serves large purchases, holidays, a house and anything
  else of the same shape, so we don't add a feature per case.
- Members attribute their own spending, so a project's total comes out right
  without the owner doing data entry.

**Bad, and the price we accept:**
- A second reporting axis means more views, and a cross-axis question such as
  "how much of the holiday was dining" needs a purpose-built view rather than a
  clever query.
- Attribution is manual, so a project's total is only as good as people's
  discipline while on holiday. The bot can ask when an expense looks like it
  belongs to an active project, and it still won't be perfect.
- One transaction belongs to one project, so a shop trip that mixes holiday and
  household items can't be split until transaction splitting exists, which spec
  0003 deliberately deferred.
- The split between classification and financial fact adds a second permission
  rule to remember and to test (ADR 0015).

**What becomes harder to change later:** splitting a transaction across projects,
if anyone ever wants it, because the single reference would then need a
migration. We record that as a known limit instead of designing around it now.
