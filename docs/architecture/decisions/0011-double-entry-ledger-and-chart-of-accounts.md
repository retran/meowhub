---
id: 0011
title: Double-entry ledger with a chart of accounts, covering cards, overdraft and loans
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amended-by: [0031]
---

# ADR 0011 - Double-entry ledger with a chart of accounts, covering cards, overdraft and loans

## Context

The household wants to be run like a small firm, and the requirements that
arrived leave no room for single-entry bookkeeping. Five of them break a flat
list of expenses:

- A credit card (ICS). A purchase happens on one date and leaves the bank
  account weeks later as one lump sum, so a naive recording spends the money
  twice: once per purchase from the card statement, and again when the bank
  statement shows the payment to ICS.
- Overdraft on debit accounts (ABN AMRO, ING). A balance that legitimately goes
  negative, with a limit that matters and interest that follows.
- A loan with interest. A monthly payment that is partly repayment of principal,
  which is not an expense at all, and partly interest, which is.
- Cash withdrawal fees on the credit card. A fee that is an expense, charged in
  the same act as a withdrawal that is not.
- Balances and cash-flow tracking, because "what do we actually have" is a
  question about accounts and not about a pile of expenses.

Double-entry was invented for exactly these five problems. The counter-argument,
that double-entry is too much ceremony for a household, we answer by hiding it,
so the person typing "coffee 350" never meets a journal.

## Decision

**The ledger is double-entry.** A *transaction* is one economic event and holds
two or more *postings*, each posting names an account and a signed amount, and
the postings of a transaction sum to exactly zero. The database enforces that
invariant (ADR 0004), not a workflow.

We own the chart of accounts and version it in migrations:

| Type | Examples | Sign convention |
|---|---|---|
| Asset | `Assets:ABN AMRO:Current`, `Assets:ING:Current`, `Assets:Cash` | Positive means the household has it. It can go negative where an overdraft exists |
| Liability | `Liabilities:ICS Credit Card`, `Liabilities:Mortgage`, `Liabilities:Loan:Car` | Positive means the household owes it |
| Income | `Income:Salary:<member>`, `Income:Other` | |
| Expense | `Expenses:Groceries`, `Expenses:Fees:Cash Advance`, `Expenses:Interest:Overdraft`, `Expenses:Interest:Loan` | |
| Equity | `Equity:Opening Balances` | Used once per account, to start from a real balance |

Six consequences fall straight out of that chart:

- A card purchase posts the expense against the card *liability* and not against
  a bank account, and paying the card bill is a transfer that takes the
  liability down and the bank account down. Paying the bill is not spending and
  never appears in a spending report, so the double-count problem disappears by
  construction instead of through a deduplication rule.
- An overdraft is an asset account with a negative balance. Each account carries
  an optional overdraft limit, which we use for alerts and forecasting and never
  for blocking, and overdraft interest posts to `Expenses:Interest:Overdraft`.
- A cash withdrawal on the card is one transaction with three postings: cash up,
  card liability up by principal plus fee, and the fee to
  `Expenses:Fees:Cash Advance`. The fee shows up as a cost and the withdrawal
  does not count as spending.
- A loan payment is one transaction split into principal, which reduces the
  liability, and interest, which is an expense. Principal repayment never
  inflates the spending reports, and since that is the single most common error
  in household bookkeeping, it is what makes this decision worth its cost.
- Borrowing costs become a report, because fees and interest have their own
  account subtree, so "what does credit cost this household per year" is one
  query.
- Balances and cash flow are derived and never stored as a mutable number: a
  balance is the sum of an account's postings and cash flow is postings over
  time. Both live in SQL views (ADR 0004), which is what the app and the digests
  read (ADR 0007).

We recognize on a cash basis, with one deliberate exception in spirit: we record
interest and fees when the bank charges them and do not accrue them daily. A
household is not required to accrue, statements are the authority (vision
principle 8), and daily accrual would create postings nobody asked for.

The complexity stays hidden, because the bot's job is to turn "coffee 350" into
a correct pair of postings using defaults: each member has a default payment
account and each merchant a default expense account, from ADR 0004's registry. A
capture that cannot be resolved into a balanced transaction becomes an unparsed
capture and a question, never a half-posted entry, and account names, postings
and the words "debit" and "credit" stay out of the bot's replies.

Multiple currencies are out of scope. Amounts are integer minor units with an
explicit currency, defaulting to EUR, and we record a foreign-currency purchase
at the amount the bank charged in EUR. Proper multi-currency accounting, with
revaluation, is a later decision if the household ever needs it.

## Alternatives

| Option | Why rejected |
|---|---|
| Single-entry list of expenses with a `paid_from` column | Where this project started, and it cannot answer the credit-card, loan or balance requirements without a growing pile of special cases, each of which is a place the numbers can be wrong |
| Double-entry but with transfers as a special transaction type outside the ledger | Recreates the double-count problem in a smaller form and makes balances unreliable, which is the thing transfers exist to keep honest |
| Full accrual accounting, with accruals and depreciation | Correct for a real firm and ceremony for a household, because nobody will post an accrual for the electricity used but not yet billed |
| Using an existing bookkeeping engine (GnuCash, Firefly III, Beancount) | Genuinely tempting, since Firefly III is self-hosted and does household double-entry well and Beancount's plain-text ledger is elegant. We rejected them because the ledger has to be the same PostgreSQL that the agent, the app and the statement importer read and write directly (ADRs 0004, 0007), and wrapping another system's database or API turns every feature into an integration. We still borrow their *account models* as the reference |
| Storing balances as a maintained column | Faster to read and wrong the first time a write is missed, while a derived balance cannot drift |

## Consequences

We gain three things:

- Cards, overdraft, loans, fees and interest are all expressible without special
  cases, and the classic double-counting errors become impossible by
  construction.
- "What do we have", "what do we owe", "what does credit cost us" and "what did
  we spend" become four different questions with four correct answers.
- Statement reconciliation gets easier instead of harder, because we match a
  bank line against postings on that specific account.

We accept four costs in return:

- The schema and every write path are more complex than a flat expense table.
  This is the project's largest deliberate complexity, and it lands in the
  database, the one place where ADR 0004 already accepted code over low-code.
- A balanced transaction is harder for an LLM to produce than a flat record, so
  the capture workflow needs defaults, validation and a refusal path instead of
  optimism.
- Somebody has to enter opening balances once per account before anything
  reconciles.
- Whoever maintains this has to understand double-entry, and in a household of
  three that is one person.

The account structure is what gets harder to change, once history is posted
against it. Renaming an account is cheap, and changing what an account *means*
is a migration over years of postings, which is why we write a conservative,
explicit chart of accounts in the first migration.
