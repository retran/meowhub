---
spec: 0003
created: 2026-09-13
updated: 2026-09-13
---

# 0003 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

Bottom-up again, and for the same reason as specs 0001 and 0002: the invariant
is built and attacked before anything writes through it, and every criterion is
closed against a running system rather than against configuration read back.
This slice is the largest of the eleven, so the order below is also the order
the tasks take — each step leaves the system working.

1. **The ledger schema**: `account`, `account_term`, `transaction`, `posting`,
   `merchant`, `merchant_alias`, `translation`, `capture`, `conversation`,
   `correction_request`, `household_setting`, and `member.default_payment_account_id`.
   `ledger_probe` — spec 0002 T4's deliberate scaffold — is dropped in the same
   migration, and its pgTAP file is rewritten against the real tables: the rules
   it proved do not change, only what they are proved on.
2. **The invariant**: postings sum to zero per transaction, enforced by a
   deferred constraint trigger, and attacked directly in pgTAP before any
   workflow exists (A6). Audit triggers on every new table, inheriting spec
   0001's `audit_log_trigger()` and its acting-member requirement (A30).
3. **Row-level security on the new tables**, in the same shape spec 0002 already
   proved on `ledger_probe`: `hh_agent` inserts what it captures, any member
   reclassifies, a member confirms or corrects only their own unconfirmed
   capture, only an admin corrects a financial fact or deletes.
4. **The views this slice needs** from the catalogue: `v_account`,
   `v_account_balance`, `v_category`, `v_period_spend`, `v_transaction_detail`,
   `v_unconfirmed`, `v_unconfirmed_summary`. Nothing computes a figure outside
   them (ADR 0040).
5. **The seed** (`db/seed/household.sql`, a placeholder since spec 0001) gains
   its real content: the starter chart and categories in both languages, and
   months of transactions including a card settlement, a cash-advance fee and a
   loan split (ADR 0015).
6. **Prompts and tools as files** (`prompts/capture-text/`, `tools/*.json`),
   with the startup check that refuses to run without them (A29).
7. **The workflows**, small and named for the job (ADR 0040): the existing
   `telegram-normalize-and-dispatch` becomes the entry point and gains one step
   — load the member's open conversation — then dispatches to `capture-text`,
   `setup-conversation`, `structural-change`, `confirm-and-correct`,
   `list-unconfirmed`, `list-recent`. `auto-confirm-quiet` is the one scheduled
   workflow, and it runs from the scheduler container like every other job.
8. **The conveniences** (R23–R27, R29): buttons with typed equivalents, undo,
   notes, "как обычно", the recent list, what-still-needs-setting-up. They are
   listed last because they depend on everything above, and they are not
   optional — they are the difference between a system that is used and one that
   is abandoned.
9. **Documentation**: `docs/guides/household-setup.md` and
   `docs/guides/talking-to-meow.md`, both new.

The one decision that shapes everything else is **which identity a write runs
as**. The bot mints its own short-lived PostgREST token per request (the pattern
spec 0002 T12 already established for the member lookup), and it mints two
shapes: `hh_agent` with the capturing member's `member_id` for a capture the
agent composed, and **the acting member's own role** — `hh_admin` or
`hh_member` — for anything the member asked for: a correction, a deletion, a
confirmation, a structural change. That is what makes A4, A14, A17 and A42 fail
at the database rather than in a workflow conditional, which is the whole point
of ADR 0039's "the tool layer never becomes a second, softer gate".

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| The agent acts as the member for requested actions, as `hh_agent` only for captures | Authorisation is RLS and nothing else; a workflow bug cannot grant permission | Two token shapes in one workflow, and the acting role has to be derived per call | **chosen** |
| The agent always acts as `hh_agent`, with permission checked in the workflow | One token shape, simpler wiring | Puts the permission model in n8n, where it drifts from RLS and is untestable by impersonation — exactly what ADR 0014 and 0039 forbid | rejected |
| Postings-sum-to-zero as an immediate per-row check | Simplest trigger | A transaction is written as several rows; an immediate check fails on the first one. A deferred constraint trigger is the only shape that works | rejected |
| Balances as a maintained column on `account` | Cheap reads | Wrong the first write that misses it (ADR 0011 rejected this explicitly) | rejected |
| Keep `ledger_probe` alongside the real tables during the transition | Nothing breaks mid-slice | Two tables claiming the same rules, and its tests would keep passing while the real ones were wrong | rejected — dropped in the same migration |
| One `capture` row per exchange, questions in a column | Matches the catalogue's current wording | R6a wants every message in order, and a single row cannot hold an exchange | rejected — `capture` becomes one row per message |
| Model-composed SQL for the capture write | Fewer moving parts | ADR 0039 rejected it outright: a model with the books' write surface, and every mistake a migration to undo | rejected |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `db/migrations/` | The ledger and its invariant; drops `ledger_probe`; RLS for every new table; the views above; `member.default_payment_account_id` | spec 0007 adds `statement_import`/`statement_line`; 0008 `account_term` usage; 0009 budgets and commitments |
| `db/seed/household.sql` | Its real content, replacing the placeholder | every slice that adds a table |
| `db/tests/` | The invariant, the write shape rewritten off `ledger_probe`, the view signatures snapshotted | grows per slice |
| `prompts/` | `capture-text/` — system prompt, output schema, examples, version | 0004 adds `query-mapping`, 0005 receipt and voice, 0007 statement |
| `tools/` | The mutating set: record, correct, confirm, classify, delete, open/amend account, merge, undo; the read set from the catalogue only | every slice that gives the agent a new action |
| `workflows/` | Entry point gains conversation loading; `capture-text`, `setup-conversation`, `structural-change`, `confirm-and-correct`, `list-unconfirmed`, `list-recent`, `auto-confirm-quiet`, and the `reply-in-language` / `call-tool` / `record-failure` sub-workflows | 0004 digests, 0005 photo and voice |
| `i18n/` | Every string this slice says: confirmations, questions, refusals, button labels, setup prompts | every slice |
| `scripts/` | `test-ledger-invariant.sh`, `test-capture-text.sh`, `test-setup-conversation.sh`, `test-corrections.sh`, `test-conveniences.sh`, `test-golden-capture.sh` | every slice |
| `docs/` | `guides/household-setup.md`, `guides/talking-to-meow.md`; `architecture/data-model.md` updated first, per its own rule | every slice |

## Contracts and data

Names come from `docs/architecture/data-model.md` and are not invented here.
Four **extensions to that catalogue are required before the migration lands**,
because it is the contract and a spec naming something it lacks is incomplete:

- **`capture` becomes one row per message**, not per exchange: `member_id`,
  `conversation_id`, `sequence`, `direction` (inbound or outbound), `kind`,
  `channel_message_id`, `raw_text`, `file_id`, `state`, `transaction_id`. R6a's
  "every message in that exchange, in order" is this table ordered by
  `sequence`; the question the agent asked is an outbound row rather than a
  column, which is also what makes A41's "not asked twice" checkable.
- **`transaction` gains `original_amount` and `original_currency`** (R28, A37).
  The catalogue lists provenance columns and no foreign-currency pair.
- **`account` gains `reviewed`** — false for a category the agent created
  unprompted (ADR 0031, R13).
- **`household_setting(key, value, updated_by, updated_at)`** is new. The
  timezone, the default currency, the auto-confirm threshold and the quiet
  period are settings the household changes, so ADR 0034 puts them in a row and
  not in the environment — and the catalogue has nowhere for them today.

Otherwise:

- **Money is integer minor units with an explicit currency**, everywhere, per the
  catalogue's own rule. `posting.amount` is signed; `transaction` holds no
  amount of its own.
- **The invariant**: a deferred constraint trigger asserts
  `sum(posting.amount) = 0` per transaction at commit, so a multi-row write is
  legal and an unbalanced one is not.
- **A category is an expense account.** There is no category table; `v_category`
  is the view of expense accounts with `translation` display names.
- **Tool declarations** (`tools/<name>.json`): stable name, one-line purpose,
  JSON input schema, required permission, mutating flag, version. The workflow
  implements the declaration; the declaration is the contract (ADR 0039).
- **Prompt reference**: a workflow names a task and a version
  (`capture-text@1`); the file is resolved from the read-only mount at startup
  and the container refuses to start if it is missing (R11d).
- **The bot's PostgREST token**: HS256 over `PGRST_JWT_SECRET`, `role` plus
  `member_id`, minted per request and short-lived — the same shape the token
  bridge mints for a browser session, and `pgrst_pre_request()` already turns
  `member_id` into `meowhub.actor` for the audit trigger.
- **No new view is invented.** `v_transaction_search` is named by R25 as where a
  note becomes searchable, and search itself is spec 0004's; this slice stores
  the note and adds nothing to that view.

## Migration and compatibility

- **`ledger_probe` is dropped** by the migration that creates `transaction` and
  `posting`. It was built in spec 0002 T4 explicitly to be superseded here; it
  holds only test fixtures, and none are migrated.
- **`member` gains `default_payment_account_id`**, nullable, referencing
  `account`. Nullable is deliberate: R0a requires capture to work after one
  account, and the edge-case table says a member with no default gets a question
  rather than a guess.
- **The seed is replaced, not migrated.** It is fixture data; nothing depends on
  its previous (empty) content.
- **Reversible.** Every migration has a `down`. The prompts, tools and workflows
  are files, re-importable by `task up`. `household_setting` rows are data and
  survive a restore like everything else.
- **No feature flag.** Nothing outside this slice reads the ledger yet — the app
  is spec 0006 and the digests are spec 0004 — so there is no client to keep in
  step.

## Verification strategy

Three levels, each doing what only it can. **pgTAP** proves the invariant, the
grants and the write shape by impersonation (`set local role`), never by reading
policy text. **Workflow tests** drive the real n8n through the real webhook with
the model gateway stubbed, the pattern `scripts/test-telegram-linking.sh`
already uses — including the multi-turn cases, which are scriptable precisely
because conversation state is in PostgreSQL (ADR 0038). **The golden set** runs
against a real model deliberately, is not part of `task test`, and its scores
are recorded in the change that touches a prompt (ADR 0025).

| Acceptance criterion | How we verify it |
|---|---|
| A1 | `test-setup-conversation.sh`: drive the interview to completion; assert each `account` row's type and that `v_account_balance` equals the stated opening balance |
| A2 | Same script: abandon after one account, send a capture against it, assert a transaction exists |
| A3 | `test-setup-conversation.sh`: admin asks to open an account and to merge two categories; assert the restatement is sent, that nothing changed before agreement, and that `audit_log.actor` is the admin's `member_id` |
| A4 | Same script as a non-admin member; assert no `account` row and a refusal — failing at the database, with the workflow asserting nothing itself |
| A5 | `test-ledger-invariant.sh`: record a withdrawal, assert `v_period_spend` for the month is unchanged; then spend the cash and assert it moves |
| A6 | pgTAP `db/tests/011_ledger_invariant.sql`: insert two postings summing to non-zero, assert the commit is rejected — attacked directly, not through a workflow |
| A7 | `test-capture-text.sh`: "coffee 350"; assert exactly two postings, the signs and accounts, today's date in the household timezone, and that nothing else changed |
| A8 | Same script: "groceries 24,40 albert heijn"; assert `24.40` and the existing merchant matched through `merchant_alias` |
| A9 | Same script: unknown merchant creates one; a second capture with a different spelling resolves to the same `merchant_id` |
| A10 | Same script with the model gateway stub configured to fail loudly if called — a known merchant's default category must be used with no model call at all |
| A11 | Same script: "on the credit card"; assert the expense posts against the card liability and no asset account appears in the transaction |
| A12 | `test-capture-text.sh` asserts the reply is one line, matches the catalogue string for the member's language, and contains none of "posting", "debit", "credit", "account" in either language |
| A13 | `test-corrections.sh` as an admin: "it was 35 not 350"; assert the amount, the follow-up confirmation, and both audit images with the admin as actor |
| A14 | Same script as a non-admin member: assert the amount is unchanged, a `correction_request` row exists, and the admins were notified |
| A15 | Same script: a non-admin member changes category and project; assert both apply |
| A16 | Same script: an admin deletes; assert no balance includes it and the audit row holds its final state |
| A17 | pgTAP, impersonating `hh_member`: `delete` on a transaction fails — and the same attempted through the bot, to show both paths refuse |
| A18 | `test-capture-text.sh`: "that was expensive"; assert no transaction, an inbound `capture` row, one outbound question row |
| A18a | `test-capture-text.sh` multi-turn: answer without the amount; assert a second, different outbound question, the capture still unparsed, and every message so far stored in order |
| A19 | Same script: answer the second question; assert the transaction is recorded and the capture closed — run for both a first answer and a later one |
| A20 | Same script with the stub returning a gateway error; assert the capture is stored unparsed, the member is told it will be handled, and nothing is written |
| A21 | Already covered by `scripts/test-telegram-linking.sh` (spec 0002 T12) — extended here to assert no transaction results |
| A22 | `scripts/test-telegram-dedup.sh` extended: the same `update_id` twice, exactly one transaction |
| A23 | `test-capture-text.sh`: captures from two members, each `transaction.submitter` asserted |
| A23a | `test-capture-text.sh`: fetch the exchange for a transaction through `v_transaction_detail`; assert the raw text byte-for-byte, and for a multi-turn capture that both messages come back in `sequence` order |
| A24 | Same script: "coffee 350 yesterday" with the household timezone set to something other than UTC; assert the booking date |
| A25 | `test-capture-text.sh` plus `auto-confirm-quiet` invoked directly: unknown merchant stays unconfirmed; known merchant below the threshold, quiet period elapsed, becomes confirmed with route recorded |
| A26 | Same script with a Russian-language member sending «кофе 350»; assert the transaction is row-for-row identical to the English case and the reply language |
| A27 | pgTAP on `v_category`: the same slug renders each member's language |
| A28 | `test-capture-text.sh` with the stub returning a response violating the declared schema; assert nothing written and the capture unparsed |
| A29 | `test-capture-text.sh`: remove a prompt file from the mount, restart n8n, assert it refuses to become healthy — the same shape as spec 0001's existing mount check |
| A30 | pgTAP: insert a transaction with no `meowhub.actor` set, under each writing role; assert rejection |
| A31 | `test-capture-text.sh`: "from savings" where no such account exists; assert no account created and one question |
| A32 | `test-conveniences.sh`: tap approve via the callback, then the typed equivalent on a second record; assert identical outcomes |
| A33 | Same script: each of two members acts, one says "undo"; assert a compensating change, the original audit rows intact, and the other member's action untouched |
| A34 | `test-capture-text.sh`: «кофе 350, подарок Маше»; assert the note on the transaction and in `v_transaction_detail` |
| A35 | `test-conveniences.sh`: "как обычно" after a known capture; assert same amount, category and account, today's date, unconfirmed |
| A36 | Same script: ask for recent captures; assert the list and that each item carries the R23 actions |
| A37 | `test-capture-text.sh`: a Swiss-franc expense with a stated EUR amount; assert both `original_amount`/`original_currency` and the EUR postings |
| A38 | `test-setup-conversation.sh`: pause, ask what remains, assert the outstanding steps and that answering resumes from there |
| A39 | Same script: pause, `docker compose restart n8n postgres`, assert the conversation resumes at the same step — which is what proves ADR 0038 |
| A40 | `test-capture-text.sh` replays the full scripted exchange — unparsed, question, partial answer, second question, resolving answer — and asserts the transaction plus every stored message. Every conversational flow gets one of these |
| A41 | Same script: run the workflow again with no new information; assert no second outbound `capture` row for the same question |
| A42 | `test-tools.sh`: each declared tool called with deliberately malformed input (nothing written) and as a member who may not use it (fails at the database, not in the workflow) |
| A43 | `test-conveniences.sh`: an admin asks in chat; assert `v_unconfirmed` is listed and one reply confirms them |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The capture prompt is good in English and weaker in Russian, or the reverse | high | One bilingual prompt with examples in both (ADR 0025), and the golden set carries both languages — a change that regresses either blocks |
| The setup interview is long enough that nobody finishes it | high | R0a is the mitigation and it is testable: A2 proves the system works after one account, so an abandoned interview is a working system rather than a broken one |
| Deferred constraint triggers behave differently under PostgREST's transaction handling than in psql | medium | A6 is proven in pgTAP and again through the real write path in `test-capture-text.sh`; both must pass |
| Auto-confirmation thresholds are wrong at first and quietly confirm guesses | medium | The conditions are conjunctive and conservative (ADR 0023), the route is recorded per row, and the threshold is a `household_setting` an admin changes without a deploy |
| The tool surface grows into a second permission model | medium | A42's negative test is per tool, and the acting-role decision above means a tool cannot grant what RLS refuses |
| The seed drifts from the real chart and stops being a useful fixture | low | It is exercised by every test in this slice, so drift shows as failures rather than as stale data |

## ADRs required

- **The acting identity of a tool call.** The agent executes a member's request
  with that member's role, and writes as `hh_agent` only for a capture it
  composed itself. ADR 0039 says a tool "carries the acting member"; it does not
  say which database role that becomes, and the answer is what makes A4, A14,
  A17 and A42 fail where they should. Draft it alongside this plan.

Everything else here is already decided: the ledger by ADRs 0011 and 0031,
conversation state by 0038, prompts by 0025, tools by 0039, workflows by 0040,
confirmation by 0023. The four `data-model.md` changes are amendments to a
contract rather than decisions, and are made there first, in the same change as
the migration that needs them.
