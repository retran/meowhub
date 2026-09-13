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

# ADR 0011 — Double-entry ledger with a chart of accounts, covering cards, overdraft and loans

## Context

The household is to be run like a small firm, and the requirements that arrived
make single-entry bookkeeping untenable. Each of these breaks a flat list of
expenses:

- **A credit card (ICS).** A purchase happens on one date and leaves the bank
  account weeks later as one lump sum. Recorded naively, the household spends the
  money twice: once per purchase from the card statement, once again when the
  bank statement shows the payment to ICS.
- **Overdraft on debit accounts (ABN AMRO, ING).** A balance that legitimately
  goes negative, with a limit that matters and interest that follows.
- **A loan with interest.** A monthly payment that is partly repayment of
  principal — not an expense at all — and partly interest, which is.
- **Cash withdrawal fees on the credit card.** A fee that is an expense, charged
  in the same act as a withdrawal that is not.
- **Balances and cash-flow tracking.** "What do we actually have" is a question
  about accounts, not about a pile of expenses.

Every one of these is the problem double-entry was invented for. The
counter-argument — that double-entry is too much ceremony for a household — is
answered by hiding it: the person typing "coffee 350" must never meet a journal.

## Decision

**The ledger is double-entry.** A *transaction* is one economic event and holds
two or more *postings*; each posting names an account and a signed amount, and
the postings of a transaction sum to exactly zero. This invariant is enforced by
the database (ADR 0004), not by a workflow.

**Chart of accounts**, owned by us and versioned in migrations:

| Type | Examples | Sign convention |
|---|---|---|
| Asset | `Assets:ABN AMRO:Current`, `Assets:ING:Current`, `Assets:Cash` | Positive = the household has it. **May go negative** where an overdraft exists |
| Liability | `Liabilities:ICS Credit Card`, `Liabilities:Mortgage`, `Liabilities:Loan:Car` | Positive = the household owes it |
| Income | `Income:Salary:<member>`, `Income:Other` | |
| Expense | `Expenses:Groceries`, `Expenses:Fees:Cash Advance`, `Expenses:Interest:Overdraft`, `Expenses:Interest:Loan` | |
| Equity | `Equity:Opening Balances` | Used once per account, to start from a real balance |

Consequences that fall straight out of it:

- **A card purchase** posts the expense against the card *liability*, not against
  a bank account. **Paying the card bill** is a transfer: liability down, bank
  account down. It is not spending, and never appears in a spending report. The
  double-count problem disappears by construction rather than by a deduplication
  rule.
- **Overdraft** is simply an asset account with a negative balance. Each account
  carries an optional overdraft limit, used for alerts and forecasting, not for
  blocking. **Overdraft interest** posts to `Expenses:Interest:Overdraft`.
- **Cash withdrawal on the card** is one transaction with three postings: cash
  up, card liability up by principal plus fee, and the fee to
  `Expenses:Fees:Cash Advance`. The fee is visible as a cost; the withdrawal is
  not treated as spending.
- **A loan payment** is one transaction split into principal (reducing the
  liability) and interest (an expense). Principal repayment never inflates the
  spending reports — the single most common error in household bookkeeping, and
  the reason this decision is worth its cost.
- **Borrowing costs are a report**, because fees and interest have their own
  account subtree: "what does credit cost this household per year" is one query.
- **Balances and cash flow are derived**, never stored as a mutable number:
  balance is the sum of an account's postings, cash flow is postings over time.
  Both live in SQL views (ADR 0004), which is what the app and the digests read
  (ADR 0007).

**Recognition is cash basis**, with one deliberate exception in spirit: interest
and fees are recorded when the bank charges them, not accrued daily. A household
is not required to accrue, statements are the authority (vision principle 8), and
daily accrual would create postings nobody asked for.

**Complexity stays hidden.** The bot's job is to turn "coffee 350" into a correct
pair of postings using defaults: each member has a default payment account, each
merchant a default expense account (ADR 0004's registry). A capture that cannot
be resolved to a balanced transaction becomes an unparsed capture and a question,
never a half-posted entry. Account names, postings and the words "debit" and
"credit" do not appear in bot replies.

**Multi-currency is not in scope.** Amounts are integer minor units with an
explicit currency, defaulting to EUR; a foreign-currency purchase is recorded at
the amount the bank charged in EUR. Proper multi-currency accounting, with
revaluation, is a later decision if it is ever needed.

## Alternatives

| Option | Why rejected |
|---|---|
| Single-entry list of expenses with a `paid_from` column | Where this project started, and it cannot answer the credit-card, loan or balance requirements without a growing pile of special cases. Each special case is a place the numbers can be wrong |
| Double-entry but with transfers as a special transaction type outside the ledger | Recreates the double-count problem in a smaller form, and makes balances unreliable — the thing transfers exist to keep honest |
| Full accrual accounting, with accruals and depreciation | Correct for a real firm, ceremony for a household. Nobody will post an accrual for the electricity used but not yet billed |
| Using an existing bookkeeping engine (GnuCash, Firefly III, Beancount) | Genuinely tempting: Firefly III is self-hosted and does household double-entry well, and Beancount's plain-text ledger is elegant. Rejected because the ledger must be the same PostgreSQL the agent, the app and the statement importer read and write directly (ADRs 0004, 0007) — wrapping another system's database or API turns every feature into an integration. Their *account models* are the reference we borrow from |
| Storing balances as a maintained column | Faster to read and wrong the first time a write is missed. Derived balances cannot drift |

## Consequences

**Good:**
- Cards, overdraft, loans, fees and interest are all expressible without special
  cases, and the classic double-counting errors are impossible by construction.
- "What do we have", "what do we owe", "what does credit cost us" and "what did
  we spend" are four different questions with four correct answers.
- Statement reconciliation gets easier, not harder: a bank line is matched
  against postings on that specific account.

**Bad, and the price we accept:**
- The schema and every write path are more complex than a flat expense table.
  This is the project's largest deliberate complexity, and it lands in the one
  place — the database — where ADR 0004 already accepted code over low-code.
- A balanced transaction is a harder thing for an LLM to produce than a flat
  record, so the capture workflow needs defaults, validation and a refusal path
  rather than optimism.
- Opening balances have to be entered once per account before anything reconciles.
- Anyone maintaining this needs to understand double-entry. For a household of
  three, that is one person.

**What becomes harder to change later:**
- The account structure, once history is posted against it. Renaming an account
  is cheap; changing what an account *means* is a migration over years of
  postings. Hence a conservative, explicit chart of accounts from the first
  migration.
