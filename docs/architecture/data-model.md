# Data model and view catalogue

The specs and the screens bind to SQL views by name — twenty-nine of them, most
mentioned in exactly one document and none defined anywhere. That is a contract
nobody had written down, and reconciling it found three pairs that were the same
thing under two names and one figure promised with no view at all.

This document is that contract. It is **not** the schema: the schema is the
migrations (ADR 0018), and where the two disagree the migrations win and this is
updated. What it fixes is the naming and the shape, so eleven specs and a design
document mean the same thing.

## Entities

Types and invariants live in migrations; the rows are data (ADR 0031).

| Entity | Holds | Notes |
|---|---|---|
| `member` | The person: role, language, theme, default payment account, active | Identity is ours (ADR 0030) |
| `member_channel` | A channel binding: kind, external id | Telegram today; an admin links it |
| `member_identity` | The identity provider's subject | One member, several sign-in methods (ADR 0032) |
| `account` | The chart of accounts: type, name, currency, parent, active | Five types, fixed in migrations (ADR 0011) |
| `account_term` | Limits, rate, payment amount and day, **effective from** | A rate change is a new row, never an edit |
| `transaction` | One economic event: date, note, project, submitter, source, confirmation state and route, model and prompt version, import | Provenance is not optional |
| `posting` | One side: account, signed amount in minor units, currency | Sums to zero per transaction, enforced in the database |
| `merchant` | Canonical name, default category, active | |
| `merchant_alias` | A raw observed string mapped to a merchant | Typed text and statement descriptors both |
| `translation` | `slug` → display name per language | Categories and account types (ADR 0017) |
| `capture` | What arrived: member, channel message id, kind, raw text, file, state, the question asked, the transaction it became | Unparsed captures live here |
| `file` | SHA-256, media type, size, original name, uploader | Content-addressed on a volume (ADR 0019) |
| `statement_import` | Account, file, format, period, closing balance, which validation was used, state, applied and reversed by | Reversible as a unit |
| `statement_line` | Normalised line: dates, amount, provider reference, descriptor, counterparty, **provenance**, match state, transaction | Authoritative or provisional (ADR 0013) |
| `budget` | Category, period, amount, rollover | |
| `commitment` | Name, account, category, amount or estimate, cadence, next due, expense or **income** | Income is modelled too |
| `planned_purchase` | Name, amount, **target date (nullable)**, priority, project, state, fulfilling transaction | A **wish** is this row with no target date (ADR 0021) |
| `project` | Name, state, target amount, target date or range | Holds no money |
| `conversation` | A multi-turn exchange in progress: member, kind, step, payload, closed | See ADR 0038 |
| `correction_request` | A member asking an admin to change a financial fact | Created by the bot, closed by the admin |
| `audit_log` | Table, row, operation, before, after, actor, when | Append-only, written by triggers (ADR 0008) |

**A category is an expense account.** There is no `category` table: ADR 0011 made
categories part of the chart of accounts, and ADR 0031 made the chart editable
data. `v_category` is the view of expense accounts with their display names. This
removes the commonest source of confusion in the specs, where "category" and
"account" sometimes meant different tables and sometimes the same one.

## The view catalogue

Every figure in the product comes from one of these. Nothing computes totals
outside the database (ADRs 0004, 0011, 0014), so this list is also the complete
answer to "what can the app and the bot show".

| View | Answers | Used by |
|---|---|---|
| `v_member` | Who is in the household, with role and linked channels | Admin screens, palette permissions |
| `v_account` | The chart, each account with its **current** term | Accounts admin, pickers |
| `v_account_balance` | Balance, limit and **headroom** per account | Home, overview, borrowing |
| `v_liability_summary` | What is owed, in total and per instrument | Overview, "сколько должны" |
| `v_cost_of_credit` | Interest and fees for a period, by instrument and kind | Borrowing, monthly digest |
| `v_category` | Expense accounts as categories, with display names per language | Everywhere a category appears |
| `v_period_spend` | Spend for a period, transfers excluded, with the unconfirmed share | Home, digests, every total |
| `v_category_spend` · `v_category_spend_by_month` | Spend per category, and one category over months | Categories screen |
| `v_merchant_spend` · `v_merchant_spend_by_month` | The same by merchant | Merchants screen |
| `v_member_spend` · `v_member_spend_by_month` | The same by member | Members screen |
| `v_period_reconciliation` | Whether a period is reconciled, per account | Shown wherever a figure is |
| `v_unconfirmed` · `v_unconfirmed_summary` | The queue, and its count and oldest age | Queue, home, the ceiling alert |
| `v_transaction_detail` | One transaction with its note, file, **and where its category came from** | Transaction screen, "почему эта категория" |
| `v_transaction_search` | Transactions matching free text over notes, merchants and captures | Search |
| `v_statement_import` · `v_statement_line` | What has been imported, and the normalised lines | Statements screen |
| `v_reconciliation_preview` | What an import would create, match, supersede and flag | Preview before applying |
| `v_budget_progress` | Spent, remaining, and the proportion of the period elapsed | Budgets |
| `v_commitment` | Obligations with next due, estimate flag, and **missed** state | Month view, alerts |
| `v_forecast` | Projected balance per account over the horizon | "Can we afford it" |
| `v_project_spend` · `v_project_feasibility` | A project's cost against its target, and whether it fits | Projects |
| `v_wish` | Undated wants, ordered by affordability | Wishlist |

## What reconciling it changed

- **`v_headroom` is gone** — headroom is a column of `v_account_balance`, not a
  view. Two names for one figure is how two screens end up disagreeing.
- **`v_account_terms` is gone** — the current term is part of `v_account`; the
  history is the `account_term` table.
- **`v_transaction_provenance` is gone** — provenance is columns of
  `v_transaction_detail`. Splitting it would have meant two queries for one screen.
- **`v_cost_of_credit` is new.** Spec 0008 promises a cost-of-credit report and
  names no view for it, so the figure existed in prose only.

## Rules

- **A view's signature is a public interface.** Its column names and types are
  snapshotted and a migration that changes one fails a test (ADR 0015).
- **Adding a figure means adding or extending a view here first.** A spec that
  names a view not in this catalogue is incomplete.
- **Money is integer minor units with an explicit currency**, everywhere, in every
  view.
- **Every spend view excludes transfers.** A transfer is not spending (ADR 0011),
  and a view that forgets it is the double-count the double-entry model exists to
  prevent.
- **Every view that reports a total also reports its unconfirmed share**, or is
  paired with one that does (ADR 0023).
