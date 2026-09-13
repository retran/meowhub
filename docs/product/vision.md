# Product vision

## What it is

meowhub is a private operations hub for a household run like a small firm. It
keeps real books — double-entry, accounts, balances, cash flow — while the people
in it just write to a chat.

Its predecessor in spirit is [nexus](https://github.com/retran/nexus), the same
idea of a "central nervous system for the household". meowhub differs in how it
is built: low-code building blocks instead of a bespoke Go service. The reason is
cost of ownership. nexus spends the admins' evenings on infrastructure; those
evenings should go into scenarios.

The two halves are deliberately asymmetric:

- **Input is conversational.** "coffee 350", a photo of a receipt, a voice note
  on the way home. Nobody fills in a form, and nobody sees an account name. The
  household talks to **Meow**, a robotic cat butler who records and withdraws
  — never comments on how the money is spent
  ([persona](../standards/agent-persona.md)).
- **The books are serious.** Every capture becomes a balanced transaction.
  Credit cards, overdrafts, loans, interest and fees are modelled properly,
  because a household that pretends a loan repayment is an expense does not know
  what it spends.

## Problem

Household bookkeeping either does not happen, or happens in an app you have to
open and fill in. The expense happens at the till, phone in one hand, bag in the
other: there is no time for six fields. So the data never gets entered, and
without data there is neither insight nor reports.

The tools that *are* serious about accounting ask a household to behave like an
accountant. The tools that are pleasant to use cannot tell a credit-card payment
from a purchase, so their totals are wrong in ways nobody notices. This household
wants both halves and is not willing to trade either.

## Who it is for

The household is three people: two parents and a daughter. All three are users,
not just the person who built it.

| Audience | Wants | Why they would use it |
|---|---|---|
| Both parents, as admins | To run the household's finances like a small firm: balances, cash flow, what credit costs, what next month looks like | Real books without real bookkeeping work; the data stays on their own hardware |
| Either of them, in a shop | To log what they spent without opening anything, and to open something on a phone later and see where the money is going | Writing to the bot like writing to a person; trends on a phone behind Face ID |
| The daughter, as a member | To log what she spends, and to see what she has left | Same chat, no separate app, no account to create |
| The household, jointly | To know whether a purchase fits this month before making it | Budgets, known commitments and planned purchases projected forward |
| Any of them, six months later | Reports, and answers to "how much do we spend on food" | The books are already there, and can be queried in plain words |

Everyone contributes to one shared set of books, and every transaction records who
submitted it. There are no private ledgers: the point is a household picture, not
three personal ones. Visibility rules per member are an open product question, not
a settled one.

## Principles

1. **Chat is the primary way in.** Capture never requires a screen. Screens exist
   for looking, not for entering.
2. **The books are true.** Only things that happened are recorded. Plans,
   budgets and forecasts live beside the ledger, never inside it.
3. **Privacy over convenience.** Household data lives where the owner controls
   it. External services only where unavoidable, and with the price acknowledged.
4. **Portability is a requirement, not a hope.** Anything that runs on rented
   hosting must move to the home server without being rewritten.
5. **Low-code means little code**, not building by mouse. Prefer ready-made
   blocks where they are genuinely less work. Two places have earned code
   deliberately: the database schema, and the household app — and the app is
   little code precisely because the schema carries the logic.
6. **The system never loses input.** If a message cannot be parsed into a
   balanced transaction, it is stored and returned as a question, never dropped
   and never half-recorded.
7. **One household, one installation.** Not multi-tenant — but multi-user:
   several people share the one installation, and **no capability belongs to one
   individual**. Both parents are admins, and every secret has two holders
   (ADR 0024), because a household's financial record must survive one person
   being unavailable.
8. **A wrong entry must be cheap to fix.** An AI that guesses will sometimes
   guess wrong; correcting it takes one message or one tap, not a database trip.
9. **The bank has the last word.** Where a hand-captured expense and a statement
   disagree, the statement is authoritative — but the capture is never silently
   discarded.
10. **Accounting vocabulary stays inside the system.** No member ever reads the
    words "debit", "posting" or "chart of accounts".
11. **Everyone sees everything; only an admin rewrites history.** One shared
    picture, and accumulated books that cannot be damaged by a stray tap
    (ADR 0016).
12. **The system asks; nobody fills in a form.** The household's own facts — its
    accounts, balances, who pays with what — are collected by Meow in
    conversation, one question at a time, never as a setup screen and never
    hard-coded by whoever built it.
13. **Russian and English, both first-class.** The interface speaks the member's
    language; the data is stored language-neutral so a label can change without
    touching a posting (ADR 0017).

## What it is not

- Not a SaaS, and not a product for other households.
- Not a tax or statutory reporting tool. The books are double-entry and cash
  basis; VAT, payroll, depreciation and filing are out of scope.
- Not a bank aggregator: we do not connect to bank APIs or PSD2 providers.
  Statements arrive as files the owner downloads and uploads himself.
- Not multi-currency accounting. Amounts are recorded in what the bank charged,
  defaulting to EUR.
- Not a general household planner. Planning here means purchases with dates and
  money; chores, meals and calendars are a different product.
- Not a full smart-home replacement. The house runs on Apple and Siemens
  equipment, which makes Apple Home and Siemens Home Connect natural integration
  targets later — appliance automation is a possible future direction, not the
  first one.

## What the system holds

- **Accounts** — the bank accounts at ABN AMRO and ING, cash, the ICS credit
  card, loans. Assets and liabilities, with balances derived from postings.
- **Transactions** — every economic event as a balanced set of postings, with
  who submitted it, in what form, and which model parsed it.
- **Merchants** — a registry that learns: recognised automatically from typed
  text and from statement descriptors, growing as new ones appear, carrying the
  default category so classification improves with use.
- **Statements** — exports from ABN AMRO, ING and ICS in whatever format they
  give us, normalised to one shape, parsed and reconciled against what was
  captured by hand.
- **Budgets, commitments and plans** — intended spending per category, the
  mandatory monthly obligations, and planned purchases with target dates.
- **Wishes and projects** — things the household wants but has not dated, and
  projects like a holiday or buying a house, which group real spending across
  categories and months against a target.
- **An audit log** — every change, every actor, every model exchange, append-only.

Every record also carries whether anyone has vouched for it: a model's guess and a
checked entry are different things, and the reports say which they are made of.

## Order of slices

| Spec | Slice | Why in this position |
|---|---|---|
| 0001 | Infrastructure bootstrap: Compose, PostgreSQL and migrations, n8n, file storage, backups, monitoring, config export | Nothing can be verified before it can be deployed, backed up and restored |
| 0002 | Identity and access: the authentication boundary, Apple sign-in, passkeys, roles, and the data path through row-level security | The boundary every later slice sits behind, and the one place a mistake leaks the household's money data. Separated from 0001 so it gets its own attention |
| 0003 | Chart of accounts, opening balances, and text expense capture | The shortest path to a working system that keeps real books: exercises the whole contour from Telegram to a balanced transaction |
| 0004 | Chat queries and a scheduled digest | Books you cannot read are useless; the push digest is what makes anyone notice them |
| 0005 | Multimodal capture: receipt photos and voice notes | One slice, because one multimodal model handles both — and easy capture is what gets the other members to actually use it |
| 0006 | Household app: trends, balances, corrections, approving records | The pull half of reporting, the thing a household member specifically asked for, and where the confirmation queue is drained |
| 0007 | Bank and card statement import with reconciliation — CAMT.053 and CSV first, PDF through the model | Turns the books from "what we remembered" into "what actually happened", and confirms records automatically; needs readable reports first to see what reconciliation did |
| 0008 | Borrowing: card settlement, overdraft interest, cash-advance fees, loan amortisation | The accounts exist from slice 0003; this is where the flows and the cost-of-credit reports land, once statements can prove them right |
| 0009 | Budgets, commitments and planned purchases, with alerts | The forecast is only meaningful on top of real balances and a real spending history |
| 0010 | Wishlist and projects: holidays, a house, large purchases | Needs the forecast from 0009 to answer "does this fit", and the reports from 0004 to show what a project actually cost |
| 0011 | Migration to the home server | Deliberately last, and deliberately its own slice: portability is verified by doing it, not assumed — and it is where the second admin rehearses a restore alone |

Each slice is a separate spec in `specs/`.

### Candidates beyond the eleven

Named so they are not rediscovered as surprises, and deliberately not specified:

| Candidate | Why it will come up |
|---|---|
| **Splitting one transaction across categories or projects** | A supermarket trip that is half holiday, half household. The known limit of ADRs 0021 and spec 0003, and the most likely first request once the books are real |
| **Several expenses in one message** | "кофе 350, обед 1200, такси 800" is how people actually talk. Deferred because partial recording is worse than asking, and asking is annoying enough that this will be wanted |
| **Money other people owe the household** | Paying for friends at dinner is common and is currently recorded as spending that never comes back. It needs a receivable, which is a small extension of double-entry and a real product decision |
| **Capture from Siri and Apple Shortcuts** | The household is entirely on Apple hardware, and "Hey Siri, expense 350 coffee" is faster than opening a chat. A shortcut that messages the bot needs no new interface |
| **Proper multi-currency** | Travel makes it wanted, and the original amounts are being stored from the start (spec 0003, R28) so the history will support it when it arrives |
| **Local model inference** | ADR 0029's fourth rung, which closes the largest residency gap. Depends on the home server's hardware |

None of these is promised. Each is written down because the cost of discovering
them late is a migration, and the cost of noting them now is a line.

## How we will know it worked

- An expense is recorded in one message, with no follow-up questions, in most
  cases — and lands as a correct balanced transaction without anyone thinking
  about accounts.
- All three household members use it, not just the person who built it.
- The books are kept continuously for a month or more, so they are genuinely
  used rather than abandoned after a week.
- Account balances agree with the bank and card statements for the same period,
  with any difference explainable rather than mysterious.
- "How much went on X during Y", "what do we owe", and "what does credit cost
  us" all have answers the owner trusts enough to act on.
- Before a significant purchase, someone actually checks whether it fits.
- A holiday or a large project can be answered for afterwards: what it cost,
  against what was intended.
- Moving to the home server takes an evening and requires no changes to the
  workflows.
