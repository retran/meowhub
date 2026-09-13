---
id: 0021
title: Projects are a second reporting axis; the wishlist is what has no date yet
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0021 — Projects are a second reporting axis; the wishlist is what has no date yet

## Context

ADR 0012 models what the household intends to spend: budgets per category per
period, recurring commitments, and planned purchases on a date. The owner then
asked for two things that do not fit those shapes.

**A wishlist.** Things the household wants, with no date and no commitment. A
planned purchase already has a target date; a wish is what exists *before* anyone
decides when.

**Projects — a holiday, buying a house.** These are not purchases. A holiday is
flights, hotels, restaurants and a car hire, spread across four categories and two
months. Buying a house is a deposit, a notary, transfer tax, a mortgage
arrangement fee and a van, spread across a year. Neither can be expressed by the
existing model:

- A **category** answers "what kind of expense", and a holiday spans several.
- A **budget** is per category and per period, and a project's budget is a
  lifetime total that does not respect month boundaries.
- A **planned purchase** is one transaction, and a project is many, most of them
  not foreseeable individually.

So a project is a different kind of thing: a **grouping of real transactions
across categories and time, with a target**.

## Decision

### Projects are a second reporting axis on the ledger

- A **project** has a name, a state, an optional target date or date range, and an
  optional target amount. States: `idea`, `planning`, `active`, `done`,
  `abandoned`.
- **A transaction may belong to one project.** That reference is a dimension on
  the transaction, orthogonal to its category — a restaurant during the holiday is
  still `Expenses:Dining`, and it is also part of `Holiday 2027`.
- **Reporting gains a second axis**: spend-to-date per project against its target,
  across every category and period it touches, alongside the existing per-category
  per-period reports. Both are SQL views (ADRs 0004, 0014), so the bot and the app
  answer identically.
- **Projects are not postings and hold no money.** Consistent with ADR 0012, a
  project's target is an expectation; the ledger records only what happened.

### Saving up is shown, never simulated

For a project with a target amount and date, the forecast answers **"does this
fit"** — projected balances from ADR 0012 against the target — and **"what would
need to be set aside per month"** to reach it.

It does **not** move money between accounts or reserve it. That would be envelope
budgeting, which ADR 0012 rejected, and it would make balances mean something
other than what the bank says.

### The wishlist is the state before a date

- A **wish** is an item with a name, an estimated amount, an optional priority and
  no date. It sits outside the forecast entirely, because an undated want is not a
  commitment.
- **Giving a wish a target date promotes it to a planned purchase** (ADR 0012),
  at which point it enters the forecast. That promotion is the only difference
  between the two, and it is deliberately one step.
- **A wish or a planned purchase may belong to a project**, so a holiday can carry
  its intended flights and its vague "maybe a day trip" at the same time.
- **When a wish is fulfilled it is linked to the transaction** that fulfilled it,
  never converted into one.

### Attribution is classification, not a financial fact

Tagging a transaction to a project, like setting its category, changes no amount,
no account and no date. It is therefore **classification, and members may do it** —
they can tag their own holiday spending as it happens.

This is a deliberate refinement of ADR 0016, which reserves editing recorded
transactions to the owner. The line is drawn at financial facts: **amount, date,
account, existence — owner only. Category and project — any member.** Without
that split the feature does not work, because a holiday would only be taggable by
one person who was not doing most of the spending.

## Alternatives

| Option | Why rejected |
|---|---|
| A project as a category, or a category subtree | Loses the real category of each expense — a holiday dinner stops being dining — and cannot express a lifetime budget across periods |
| Free-text tags on transactions | Would cover projects and everything else, and decays immediately: three spellings of one holiday and no target, no state, no report |
| A project as a separate ledger or set of accounts | Double-entry purity at the cost of usability: transfers in and out of a "holiday account" that does not exist at any bank, and balances that no longer match the statements |
| Reserving money for a project in a real sub-account | Envelope budgeting by another name, already rejected in ADR 0012, and it makes account balances disagree with the bank |
| Wishes and planned purchases as one thing with a nullable date | Nearly what this is — the difference is that a dated item enters the forecast and an undated one must not. Keeping one table with an explicit state is fine; keeping one *concept* is what would blur it |
| A general project management module — tasks, deadlines, checklists | The vision's "not a general household planner" holds. A project here is money with a name and a target, not work to be tracked |

## Consequences

**Good:**
- "What did the holiday actually cost" and "can we afford the house deposit by
  March" become answerable, which is the point of running a household like a firm.
- A wish costs nothing to write down and does not pollute the forecast until
  someone commits to a date.
- One extra dimension serves large purchases, holidays, a house and anything else
  of the same shape, rather than a feature per case.
- Members can attribute their own spending, so a project's total is right without
  the owner doing data entry.

**Bad, and the price we accept:**
- A second reporting axis means more views, and cross-axis questions — "how much
  of the holiday was dining" — need purpose-built views rather than clever
  queries.
- Attribution is manual, and a project's total is only as good as people's
  discipline while on holiday. The bot can help by asking when an expense looks
  like it belongs to an active project, but it will not be perfect.
- One transaction, one project: a shop trip that mixes holiday and household
  items cannot be split until transaction splitting exists, which spec 0003
  deliberately deferred.
- The classification-versus-fact split adds a second permission rule to hold in
  mind and to test (ADR 0015).

**What becomes harder to change later:** if splitting a transaction across
projects is ever wanted, the single reference becomes a migration. Recorded as a
known limit rather than designed around now.
