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
| `member` | The person: role, language, theme, default payment account, active, digest preferences | Identity is ours (ADR 0030). Language and theme are the member's own to change (spec 0006 R6b/R6c), which is narrower than "admins edit" and needs its own policy |
| `member_channel` | A channel binding: kind, external id | Telegram today; an admin links it |
| `member_identity` | The identity provider's subject | One member, several sign-in methods (ADR 0032) |
| `account` | The chart of accounts: type, name, currency, parent, active, **reviewed** | Five types, fixed in migrations (ADR 0011). `reviewed` is false for a category the agent created unprompted (ADR 0031) |
| `account_term` | Limits, rate, payment amount and day, **effective from** | A rate change is a new row, never an edit |
| `transaction` | One economic event: date, note, project, **merchant**, submitter, source, confirmation state and route, model and prompt version, import, **original amount and currency**, **category source**, **inferred fields** | Provenance is not optional. The original pair is kept where an expense was charged in another currency — it costs nothing now and cannot be recovered later (spec 0003 R28). category_source (merchant default, model, or manual) is `v_transaction_detail`'s "why this category"; inferred_fields is what `v_unconfirmed` marks |
| `posting` | One side: account, signed amount in minor units, currency | Sums to zero per transaction, enforced in the database |
| `merchant` | Canonical name, default category, active | |
| `merchant_alias` | A raw observed string mapped to a merchant | Typed text and statement descriptors both |
| `translation` | `slug` → display name per language | Categories and account types (ADR 0017) |
| `capture` | **One row per message**, inbound and outbound: member, conversation, **chat**, sequence, direction, kind, channel message id, raw text, file, extracted payload, state, the transaction it became | The whole exchange that produced a record, in order (spec 0003 R6a) — the question the agent asked is an outbound row, not a column, which is what makes "not asked twice" checkable. Unparsed captures live here; so do a receipt's line items and a voice note's transcript. chat_id (distinct from member_id) is what a shared-group-chat query for context filters on (ADR 0043) |
| `file` | SHA-256, media type, size, original name, uploader | Content-addressed on a volume (ADR 0019) |
| `statement_import` | Account, file, format, period, closing balance, which validation was used, state, applied and reversed by | Reversible as a unit |
| `statement_line` | Normalised line: dates, amount, provider reference, descriptor, counterparty, **provenance**, match state, transaction | Authoritative or provisional (ADR 0013) |
| `budget` | Category, period, amount, rollover | |
| `commitment` | Name, account, category, amount or estimate, cadence, next due, expense or **income** | Income is modelled too |
| `planned_purchase` | Name, amount, **target date (nullable)**, priority, project, state, fulfilling transaction | A **wish** is this row with no target date (ADR 0021) |
| `project` | Name, state, target amount, target date or range | Holds no money |
| `conversation` | A multi-turn exchange in progress: member, kind, step, payload, closed | See ADR 0038 |
| `correction_request` | A member asking an admin to change a financial fact | Created by the bot, closed by the admin |
| `agent_memory` | A standing fact the agent keeps: member (nullable — null is household-wide), content, when | Distinct from the ledger and from conversation (ADR 0044); never a financial fact |
| `household_setting` | `key`, `value`, who changed it and when | The timezone, the default currency, the auto-confirm threshold and quiet period, the "does this belong to a project?" threshold, the matching tolerance. A setting the household changes is a row, never an environment variable (ADR 0034) — and there was nowhere for one until now |
| `model_exchange` | One model call: task, prompt version, model, latency, cost, outcome | ADR 0008 requires it and ADR 0029 prices it. A refused or failed attempt has a cost and **no** transaction, so this cannot be columns on `transaction` |
| `alert_state` | `kind`, subject, period, when it fired, when it cleared | "Once per condition" is a fact that must survive a restart. Three slices need the same mechanism — the queue ceiling (ADR 0023), the credit-limit warning, the budget and commitment alerts — so it is one entity, not three re-derivations |
| `digest_run` | Member, kind, period start, sent at | Scheduling state, deliberately not a view: unique on its first three columns, so the insert is the send's gate and a restart cannot double-send |
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
| `v_liability_summary` | What is owed, per liability and in total (the row with `account_id` null) | Overview, "сколько должны" |
| `v_household_position` | What the household holds in total, what it owes in total, and its net position | Overview, "какое у нас положение" |
| `v_cost_of_credit` | Interest and fees for a period, by instrument and kind | Borrowing, monthly digest |
| `v_loan_schedule` | The amortisation schedule, derived from the liability's actual balance | Borrowing. A **forecast**, and ADR 0012 means it creates no postings — derived rather than stored is what makes that hold by construction |
| `v_category` | Expense accounts as categories, with display names per language | Everywhere a category appears |
| `v_reporting_period` | Every period this household can currently be asked about, with its bounds and its previous period's own bounds (ADR 0045) | Every spend view below joins this once rather than resolving a period per question |
| `v_period_spend` | Spend for a period, transfers excluded, with the unconfirmed share | Home, digests, every total |
| `v_category_spend` · `v_category_spend_by_month` | Spend per category, and one category over months | Categories screen |
| `v_merchant_spend` · `v_merchant_spend_by_month` | The same by merchant | Merchants screen |
| `v_member_spend` · `v_member_spend_by_month` | The same by member | Members screen |
| `v_period_reconciliation` | Whether a period is reconciled — always `false` until spec 0007 gives it a real statement to reconcile against, stated rather than omitted | Shown wherever a figure is |
| `v_unconfirmed` · `v_unconfirmed_summary` | The queue, its count and oldest age, and **which fields were inferred** rather than stated | Queue, home, the ceiling alert. The screens mark inferred fields, so the marker is part of the contract |
| `v_transaction_detail` | One transaction with its note, file, **and where its category came from** | Transaction screen, "почему эта категория" |
| `v_transaction_search` | Transactions matching free text over notes, merchants and captures, with the amount each came to | Search |
| `v_merchant_lookup` | Every string a merchant can be recognised by — its own name and each alias — with the category it defaults to | The agent's `find_merchant`: deciding whether a shop is one we already know (ADR 0046) |
| `v_statement_import` · `v_statement_line` | What has been imported, and the normalised lines | Statements screen |
| `v_reconciliation_preview` | What an import would create, match, supersede and flag | Preview before applying |
| `v_budget_progress` | Spent, remaining, and the proportion of the period elapsed | Budgets |
| `v_commitment` | Obligations with next due, estimate flag, and **missed** state | Month view, alerts |
| `v_forecast` | Projected balance per account over the horizon, with **what is committed** and **what is budgeted and unspent** | "Can we afford it". The horizon must reach a project's target date or say plainly that it does not |
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

## What planning the remaining slices added

Writing `plan.md` for specs 0003–0011 found things every one of them needed and
none of them had anywhere to put. They are listed here rather than invented nine
times, because that is what this document is for.

- **`household_setting` is new, and it is the largest gap.** The timezone, the
  default currency, the auto-confirm threshold and quiet period, the "does this
  belong to a project?" threshold, the matching tolerance — ADR 0034 says a
  setting the household changes is a row, and there was no row to change.
- **`model_exchange` is new.** ADR 0008 requires the prompt, model and cost of
  every call, and a refused or failed attempt has a cost and no transaction to
  hang it on. Spec 0003 creates it; spec 0005 is the slice that cannot do
  without it.
- **`alert_state` is new.** "Once per condition" appears in three slices and
  needs state that survives a restart in all three.
- **`digest_run` is new**, and deliberately not a view — it is how a restart is
  stopped from double-sending.
- **`capture` became one row per message.** The full exchange that produced a
  record is the requirement (spec 0003 R6a); the agent's own question is an
  outbound row, which is also what makes "never asked twice" checkable.
- **`v_loan_schedule` is new**, and derived rather than stored, which is how
  ADR 0012's "a forecast creates no postings" holds by construction.
- **Two figures gained columns rather than views**: `v_unconfirmed` says which
  fields were inferred, and `v_forecast` says what is committed and what is
  budgeted and unspent. The alternative was three more view names for one screen.

## Rules

- **Every view is created `WITH (security_invoker = true)`.** A view otherwise
  runs with its owner's rights and reads straight past row-level security — which
  would silently undo the whole of spec 0002 while every test that does not
  impersonate still passed. This is asserted by impersonating a role and reading
  through the view, never by reading the view's definition.
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
