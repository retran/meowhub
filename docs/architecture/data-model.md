# Data model and view catalogue

The specs and the screens bind to SQL views by name - twenty-nine of them, most
mentioned in exactly one document and none defined anywhere. Nobody had written
that contract down, so when we reconciled it we found three pairs that were the
same thing under two names, and one figure promised with no view behind it at
all.

We wrote that contract down here, and it is not the schema. The migrations are
the schema (ADR 0018), so when the two disagree we follow the migrations and
update this page. What the catalogue settles is the naming and the columns, so
that eleven specs and a design document mean the same thing by the same word.

## Entities

The migrations hold the types and the invariants; the rows themselves are data
the household edits (ADR 0031). Each entity below names what it holds and the
decision that put it there.

| Entity | Holds | Notes |
|---|---|---|
| `member` | The person: role, language, theme, default payment account, active, digest preferences | We own identity (ADR 0030). A member changes their own language and theme (spec 0006 R6b/R6c), which is narrower than "admins edit" and so needs its own policy |
| `member_channel` | A channel binding: kind, external id | Telegram today; an admin links it |
| `member_identity` | The identity provider's subject | One member, several sign-in methods (ADR 0032) |
| `account` | The chart of accounts: type, name, currency, parent, active, reviewed | The migrations fix the five types (ADR 0011). `reviewed` is false for a category the agent created unprompted (ADR 0031) |
| `account_term` | Limits, rate, payment amount and day, effective from | A rate change inserts a new row, so we never edit one |
| `transaction` | One economic event: date, note, project, merchant, submitter, source, confirmation state and route, model and prompt version, import, original amount and currency, category source, inferred fields | Every transaction records its provenance. We keep the original amount and currency whenever an expense was charged in another currency, because storing the pair costs nothing now and we cannot recover it later (spec 0003 R28). `category_source` (merchant default, model, or manual) is how `v_transaction_detail` answers "why this category", and `inferred_fields` is what `v_unconfirmed` marks |
| `posting` | One side: account, signed amount in minor units, currency | The database enforces that the postings of a transaction sum to zero |
| `merchant` | Canonical name, default category, active | |
| `merchant_alias` | A raw observed string mapped to a merchant | Typed text and statement descriptors both |
| `translation` | `slug` to display name per language | Categories and account types (ADR 0017) |
| `capture` | One row per message, inbound and outbound: member, conversation, chat, sequence, direction, kind, channel message id, raw text, file, extracted payload, state, the transaction it became | Spec 0003 R6a asks for the whole exchange that produced a record, in order. The question the agent asked is an outbound row and not a column, which is what lets a test check that nobody was asked twice. Unparsed captures live here, and so do a receipt's line items and a voice note's transcript. `chat_id` is distinct from `member_id`, and it is what a query filters on when it pulls context from a shared group chat (ADR 0043) |
| `file` | SHA-256, media type, size, original name, uploader | Content-addressed on a volume (ADR 0019) |
| `statement_import` | Account, file, format, period, closing balance, which validation was used, state, applied and reversed by | You reverse an import as a unit |
| `statement_line` | Normalised line: dates, amount, provider reference, descriptor, counterparty, provenance, match state, transaction | Authoritative or provisional (ADR 0013) |
| `budget` | Category, period, amount, rollover | |
| `commitment` | Name, account, category, amount or estimate, cadence, next due, expense or income | We model income here too, not only what goes out |
| `planned_purchase` | Name, amount, target date (nullable), priority, project, state, fulfilling transaction | A wish is this row with no target date (ADR 0021) |
| `project` | Name, state, target amount, target date or range | Holds no money |
| `conversation` | A multi-turn exchange in progress: member, kind, step, payload, closed | ADR 0038 explains the model |
| `correction_request` | A member asking an admin to change a financial fact | The bot creates it and the admin closes it |
| `agent_memory` | A standing fact the agent keeps: member (nullable, where null means household-wide), content, when | Separate from the ledger and from `conversation` (ADR 0044); it never holds a financial fact |
| `household_setting` | `key`, `value`, who changed it and when | The timezone, the default currency, the auto-confirm threshold and quiet period, the "does this belong to a project?" threshold, and the matching tolerance. ADR 0034 says a setting the household changes is a row and never an environment variable, and until this table there was no row to change |
| `model_exchange` | One model call: task, prompt version, model, latency, cost, outcome | ADR 0008 requires it and ADR 0029 prices it. A refused or failed attempt costs money and produces no transaction, so these cannot be columns on `transaction` |
| `alert_state` | `kind`, subject, period, when it fired, when it cleared | "Once per condition" has to survive a restart, so it lives in a table. Three slices need the same thing - the queue ceiling (ADR 0023), the credit-limit warning, and the budget and commitment alerts - so we built one entity and not three |
| `digest_run` | Member, kind, period start, sent at | Scheduling state, and we kept it out of the views on purpose: it is unique on its first three columns, so the insert is what gates the send and a restart cannot send twice |
| `audit_log` | Table, row, operation, before, after, actor, when | Append-only, written by triggers (ADR 0008) |

We deliberately built no `category` table, because ADR 0011 made categories part
of the chart of accounts and ADR 0031 made that chart editable data. A category
is an expense account, and `v_category` is the view of expense accounts with
their display names. Settling this removed the commonest confusion in the specs,
where "category" and "account" sometimes meant two tables and sometimes one.

## The view catalogue

Every figure in the product comes from one of the views below. Nothing computes
a total outside the database (ADRs 0004, 0011, 0014), so this list also answers
in full what the app and the bot can show.

| View | Answers | Used by |
|---|---|---|
| `v_member` | Who is in the household, with role and linked channels | Admin screens, palette permissions |
| `v_account` | The chart, each account with its current term | Accounts admin, pickers |
| `v_account_balance` | Balance, limit and headroom per account | Home, overview, borrowing |
| `v_liability_summary` | What is owed, per liability and in total (the row with `account_id` null) | Overview, "сколько должны" |
| `v_household_position` | What the household holds in total, what it owes in total, and its net position | Overview, "какое у нас положение" |
| `v_cost_of_credit` | Interest and fees for a period, by instrument and kind | Borrowing, monthly digest |
| `v_loan_schedule` | The amortisation schedule, derived from the liability's actual balance | Borrowing. It is a forecast, and ADR 0012 says a forecast creates no postings; deriving the schedule instead of storing it makes that hold by construction |
| `v_category` | Expense accounts as categories, with display names per language | Everywhere a category appears |
| `v_reporting_period` | Every period this household can currently be asked about, with its bounds and its previous period's own bounds (ADR 0045) | Every spend view below joins this once, so none of them resolves a period per question |
| `v_period_spend` | Spend for a period, transfers excluded, with the unconfirmed share | Home, digests, every total |
| `v_category_spend`, `v_category_spend_by_month` | Spend per category, and one category over months | Categories screen |
| `v_merchant_spend`, `v_merchant_spend_by_month` | The same by merchant | Merchants screen |
| `v_member_spend`, `v_member_spend_by_month` | The same by member | Members screen |
| `v_period_reconciliation` | Whether a period is reconciled. It returns `false` until spec 0007 gives it a real statement to reconcile against, and we say so instead of leaving the view out | Shown wherever a figure is |
| `v_unconfirmed`, `v_unconfirmed_summary` | The queue, its count and oldest age, and which fields were inferred instead of stated | Queue, home, the ceiling alert. The screens mark inferred fields, so that marker is part of the contract |
| `v_transaction_detail` | One transaction with its note, its file, and where its category came from | Transaction screen, "почему эта категория" |
| `v_transaction_search` | Transactions matching free text over notes, merchants and captures, with the amount each came to | Search |
| `v_merchant_lookup` | Every string a merchant can be recognised by - its own name and each alias - with the category it defaults to | The agent's `find_merchant`, which decides whether a shop is one we already know (ADR 0046) |
| `v_statement_import`, `v_statement_line` | What has been imported, and the normalised lines | Statements screen |
| `v_reconciliation_preview` | What an import would create, match, supersede and flag | Preview before applying |
| `v_budget_progress` | Spent, remaining, and the proportion of the period elapsed | Budgets |
| `v_commitment` | Obligations with next due, estimate flag, and missed state | Month view, alerts |
| `v_forecast` | Projected balance per account over the horizon, with what is committed and what is budgeted and unspent | "Can we afford it". The horizon must reach a project's target date, or say plainly that it does not |
| `v_project_spend`, `v_project_feasibility` | A project's cost against its target, and whether it fits | Projects |
| `v_wish` | Undated wants, ordered by affordability | Wishlist |

## What reconciling it changed

Reconciling the twenty-nine names against the specs removed three views and
added one. Each change below says what we did and what it bought.

- We dropped `v_headroom`, because headroom is a column of `v_account_balance`.
  Two names for one figure is how two screens end up disagreeing.
- We dropped `v_account_terms`, because `v_account` already carries the current
  term and the `account_term` table holds the history.
- We dropped `v_transaction_provenance`, because provenance is columns of
  `v_transaction_detail`, and splitting it would have made one screen run two
  queries.
- We added `v_cost_of_credit`, because spec 0008 promises a cost-of-credit
  report and names no view for it, so the figure existed only in prose.

## What planning the remaining slices added

Writing `plan.md` for specs 0003 to 0011 turned up things every one of those
slices needed and none of them had anywhere to put. We list them here so that
nobody invents them nine times over.

- We added `household_setting`, and it closed the largest gap. ADR 0034 says a
  setting the household changes is a row, and there was no row to change for the
  timezone, the default currency, the auto-confirm threshold and quiet period,
  the "does this belong to a project?" threshold, or the matching tolerance.
- We added `model_exchange`, because ADR 0008 requires the prompt, model and
  cost of every call, and a refused or failed attempt costs money and leaves no
  transaction to hang it on. Spec 0003 creates it, and spec 0005 is the slice
  that cannot do without it.
- We added `alert_state`, because "once per condition" appears in three slices
  and needs state that survives a restart in all three.
- We added `digest_run`, and kept it as a table so that a restart cannot
  double-send.
- We changed `capture` to one row per message, because spec 0003 R6a asks for
  the full exchange that produced a record, and putting the agent's own question
  in an outbound row is what lets a test check that nobody was asked twice.
- We added `v_loan_schedule` and derived it instead of storing it, which is how
  ADR 0012's rule that a forecast creates no postings holds by construction.
- We gave two figures extra columns and no new view: `v_unconfirmed` says which
  fields were inferred, and `v_forecast` says what is committed and what is
  budgeted and unspent. The alternative was three more view names feeding one
  screen.

## Rules

Six rules govern every view in the catalogue. They cover security, the stability
of a view's columns, how a new figure arrives, and the three arithmetic mistakes
we refuse to let a view make.

- Create every view `WITH (security_invoker = true)`. A view otherwise runs with
  its owner's rights and reads straight past row-level security, which would
  undo the whole of spec 0002 while every test that does not impersonate still
  passed. We assert this by impersonating a role and reading through the view,
  never by reading the view's definition.
- Treat a view's signature as a public interface. We snapshot its column names
  and types, and a migration that changes one fails a test (ADR 0015).
- Add or extend a view here before you add a figure, because a spec that names a
  view not in this catalogue is incomplete.
- Store money as integer minor units with an explicit currency, everywhere, in
  every view.
- Exclude transfers from every spend view. A transfer is not spending (ADR
  0011), and a view that forgets it produces the double-count the double-entry
  model exists to prevent.
- Report the unconfirmed share alongside every total, either in the same view or
  in one paired with it (ADR 0023).
