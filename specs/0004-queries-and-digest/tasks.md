---
spec: 0004
created: 2026-09-13
updated: 2026-09-14
---

# 0004 - Tasks

Work the tasks in order: start one only once its dependencies are closed. Each
task is one logical commit that leaves the project in a working state.

Legend: `[ ]` not started, `[~]` in progress, `[x]` done, `[-]` dropped.

## Tasks

- [x] **T1.** The ADR the plan requires, "reporting periods are a fixed
      vocabulary resolved in SQL" (ADR 0045), plus the single function every
      later view calls: `period_bounds(period, household_tz)`, which resolves
      `this_month`, `last_month`, `month_of:YYYY-MM`, `this_year`, `last_year`,
      `last_7_days` and `last_30_days` to `period_start`/`period_end` and the
      matching previous period's bounds, in the household's own timezone and
      never a server's.
  - Depends on: none
  - Requirements: underlies R2, R4, R18
  - Done when: a pgTAP test resolves every fixed period name against a
      household on a non-UTC timezone and checks the bounds by hand, and an
      unrecognised period name is rejected rather than guessed at.

- [x] **T2.** The spend-view family: rework `v_period_spend` and add
      `v_category_spend`, `v_category_spend_by_month`, `v_merchant_spend`,
      `v_merchant_spend_by_month`, `v_member_spend`, `v_member_spend_by_month`.
      Every row carries `period`, `period_start`, `period_end`,
      `amount_minor`, `previous_amount_minor`, `delta_minor`,
      `unconfirmed_amount_minor` and `unconfirmed_share`, so the previous
      period is a column (R18) and never a second query. Transfers are excluded
      by construction, and every view is created
      `WITH (security_invoker = true)`.
  - Depends on: T1
  - Requirements: R2 (spending), R3, R4, R18
  - Done when: A4, A6, A17 pass in pgTAP against the seeded household, each
      figure checked against an aggregation written independently in the test.

- [x] **T3.** Holdings and liabilities: `v_liability_summary` (per liability
      and in total) and `v_household_position` (holdings, owed, net position).
      Headroom stays a column on `v_account_balance`.
  - Depends on: T1
  - Requirements: R2 (accounts), R2a
  - Done when: A5 and A5a pass in pgTAP, so that a balance equals the
      independent sum of an account's postings, and holdings, owed, net
      position and headroom are each answerable from their own view.

- [x] **T4.** Search and the reconciliation stub: `v_transaction_search` (GIN
      over note, merchant and capture text via `unaccent`/`pg_trgm`) and
      `v_period_reconciliation`, which reports "not reconciled" until spec 0007
      gives it something to read, and states that rather than omit it.
  - Depends on: T1
  - Requirements: R19, R17
  - Done when: A18 passes in pgTAP, and `v_period_reconciliation` is queried
      directly to confirm it reports "not reconciled" everywhere.

- [x] **T5.** The read-tool registry: one declared tool per answerable question
      (spec 0003's format, ADR 0039), covering spending totals, by category, by
      merchant, by member, their trends, account balance, household position,
      liabilities, movement, largest expenses, unconfirmed summary, search, why
      this category, and export.
  - Depends on: T2, T3, T4
  - Requirements: R2a, R5, R23
  - Done when: A5b passes, so that every view has a read tool or a committed
      exemption, and `docs/guides/talking-to-meow.md` matches the registry.

- [x] **T6.** The tools the agent needs in order to *choose* rather than be
      handed a choice (ADR 0046): `find_merchant` (against the alias registry),
      `create_merchant`, `find_category`, `create_category`, `find_account`.
      Today spec 0003's `capture-text` does each of these by substring-matching
      a list in JavaScript. `v_merchant_lookup` makes "do we already know this
      shop?" one filtered read over every name and alias. The executors
      themselves belong to the dispatcher and land with it in T7, because a tool
      is a declaration plus a permission boundary here, and a dispatch entry
      there.
  - Depends on: T5
  - Requirements: R5; spec 0003's R12, R13
  - Done when: each tool is declared, and proven by impersonation in pgTAP:
      `v_merchant_lookup` finds a merchant by name and by each alias, returns
      its default category, and returns nothing for a name nobody has used, so
      that "this is new" is a decision rather than an empty result. The agent
      composes merchants and aliases, and a member writing the registry
      directly is refused.

- [x] **T7.** The agent loop: one system prompt (`prompts/agent/v1/`), one
      workflow, a bounded round cap, and a dispatcher that executes a tool call
      by name, minting the acting identity's token itself (ADR 0042) rather
      than trusting the model to name an authority. The model gateway stub
      gains tool-call responses, because that is what a real model returns.
  - Depends on: T6
  - Requirements: R1, R5, R6, R7, R8
  - Done when: A3 and A13 pass in `scripts/test-agent-loop.sh`: a question no
      tool answers is refused in the agent's own words naming what can be
      asked; an unreachable gateway degrades to a stored message and an honest
      sentence; and a stubbed model that only ever calls tools stops at the
      round cap rather than looping.

- [x] **T8.** Answering, end to end: the agent calls read tools and writes the
      reply itself, in the member's language, with the period and the
      unconfirmed share (R3), the previous period's figure (R18), and buttons
      where a question offers a closed choice (R22).
  - Depends on: T7
  - Requirements: R1, R2, R3, R7, R8, R18, R22
  - Done when: A1, A1a, A2, A4, A5a, A6, A15, A17 pass in
      `scripts/test-answer-question.sh`, and A14 passes in
      `scripts/test-figure-traceability.sh`, so that every number in the reply
      appears in a tool result from that exchange and none appears that does
      not. A14 is the gate for this task: until it passes, the agent must not
      answer with figures at all.

- [x] **T9a.** Migrate capture onto the loop: the entry point's capture
      route dispatches to the agent instead of `capture-text`, and the loop
      takes over the conversation bookkeeping that workflow did, which means
      opening a clarification conversation when the agent asks a question,
      attaching every message to it, closing it when a transaction is
      recorded, and never storing the same question twice. Setup, corrections
      and structural changes keep their own routes until T9b and T9c, so
      nothing is broken while this is proven.
  - Depends on: T8
  - Requirements: ADR 0046; spec 0003's R8 to R14, R17, R6a
  - Done when: `test-capture-text.sh` and `test-auto-confirm-quiet.sh` pass
      unchanged, and `workflows/capture-text.json` and
      `prompts/capture-text/` are gone.

- [x] **T9b.** Migrate corrections and the conveniences: correcting an
      amount or a merchant, reclassifying, deleting, confirming (tapped or
      typed), undo, remember, "same again", the recent list and the admin
      queue all become tool calls the agent makes.
  - Depends on: T9a
  - Requirements: ADR 0046; spec 0003's R15 to R16a, R20, R23 to R27
  - Done when: `test-corrections.sh`, `test-conveniences.sh` and
      `test-admin-queue.sh` pass, and `workflows/correction.json` is gone.
      One assertion in `test-conveniences.sh` names the `correction0001`
      workflow rather than a behaviour and has to change with it, which we
      record in the deviation log, asserting instead the behaviour it was
      standing in for.

- [x] **T9c.** Migrate setup and structural changes: opening accounts,
      opening balances, household settings and a default payment account
      become a conversation the agent has with tools it already has, rather
      than a step machine.
  - Depends on: T9b
  - Requirements: ADR 0046; spec 0003's R0 to R0f, R29
  - Done when: setup and structural changes work end to end and
      `workflows/setup-conversation.json`, `workflows/structural-change.json`,
      `prompts/setup-conversation/` and the `Route Message` regexes are gone.
      `test-setup-conversation.sh` asserts `conversation.step` values, which
      are the old step machine's internal state and not a behaviour spec 0003
      requires, so we rewrite those assertions to assert what R0e actually
      asks, that a paused setup survives a restart and resumes, and record the
      change in the deviation log.

- [x] **T10.** Search, "why this category" and export become ordinary tools the
      agent calls, with no trigger phrases and no workflows of their own.
  - Depends on: T8
  - Requirements: R19, R20, R21
  - Done when: A18, A19 and A20 pass, with the export's CSV diffed against
      `v_period_spend` for the same period and parsed as RFC 4180.

- [x] **T11.** `digest_run(member_id, kind, period_start, sent_at)`,
      `member.digest_weekly`/`digest_monthly` (default true), and `digest-tick`,
      which runs hourly and lets SQL decide who is due and unsent, so that the
      insert into `digest_run` is the send's own gate and idempotent by
      construction. The tick drives
      `send-weekly-digest`/`send-monthly-digest`. It stays model-free: SQL and
      a template, reading the same views the agent's tools read (R13).
  - Depends on: T2, T3
  - Requirements: R9, R10, R11, R13, R15, R16, R17, R18
  - Done when: A7, A8, A9, A10, A16 pass in `scripts/test-digest.sh` with the
      clock moved in SQL (Monday 08:59, 09:00, 09:01, and the 1st) rather than
      waited for.

- [x] **T12.** The digest heartbeat and the persona gate: a heartbeat push to
      Uptime Kuma on every successful tick (ADR 0020), and a committed
      forbidden-word check run against the digest templates themselves, so that
      no accounting vocabulary or judgement can be smuggled into a string (R12).
  - Depends on: T11
  - Requirements: R12, R14
  - Done when: A11 passes (`scripts/test-digest-heartbeat.sh`: prevent a tick,
      let the window pass, assert the alert) and A12 passes
      (`scripts/test-digest-language.sh` against the templates, not a sample).

- [x] **T13.** The agent's golden set, run for real (ADR 0025): bilingual cases
      covering capture *and* questions in one set, because one prompt now
      serves both and a change made for one can regress the other. We record
      the scores in the commit and never make the set part of `task test`.
  - Depends on: T9
  - Requirements: ADR 0025, ADR 0046
  - Done when: the golden set runs against a real model and its scores are
      recorded in `prompts/agent/v1/golden-set-results.json`, covering at
      minimum a bare capture, a capture needing a question, a correction, a
      spend question, a ranked question, an account question, and a refusal,
      in both languages.

## Deviation log

Where the work had to depart from the plan, record here what changed and why,
and fix the spec or the plan to match.

| Date | What changed | Why |
|---|---|---|
| 2026-09-14 | `test-forced-password-change.sh` and `test-deactivation.sh` now delete their Authentik fixture user in cleanup (`scripts/delete-authentik-user.sh`). | Neither did, so each passed once on a fresh Authentik and failed on every rerun with a `KeyError: 'pk'`, because Authentik refused `create-member.sh`'s user creation for a duplicate username. The suite is the gate for a slice, so a suite that only passes once is not a gate. |
| 2026-09-14 | `immutable_unaccent` is schema-qualified with its own pinned `search_path` (migration `20260914100000_immutable_unaccent_restorable.sql`). | The full suite caught it: `test-restore-verification.sh` could not load a dump of this database back. The function called `unaccent('unaccent', $1)` unqualified, which resolves in an ordinary session but not during a restore, whose search_path is pinned to pg_catalog, and the trigram indexes that call it are built as the dump loads. We were backing the books up without being able to restore them, which is exactly the failure ADR 0009's verified restore exists to catch. |
| 2026-09-14 | Every test script that restarts n8n now waits with `scripts/wait-for-n8n.sh` instead of its own "healthy" loop, which means healthy plus the health-check webhook actually answering, plus a second for the remaining workflows to register. | n8n reports healthy as soon as its HTTP server is listening, a moment before it has re-registered the webhook paths of the active workflows. A test posting in that gap gets a 404 and reads it as the behaviour being wrong: `test-capture-text.sh` failed its first case in a full-suite run and passed alone, and the same gap had already cost a run of `test-digest.sh`. |
| 2026-09-14 | T13's golden set scores 15/16 against `openai/gpt-4o-mini`, not 16/16. The one failure is `ranked-question-en`, which reached for `spend_total` instead of `spend_by_category`; the Russian equivalent passes, and the English one passed on the previous run of the same prompt. | We recorded it rather than chase it, because it is model variance on a question whose two candidate tools both answer something reasonable, and not a defect the prompt can state its way out of. We fixed the three real defects the first run did find: the period argument was a free string (a model invented `2026-08`, so every declaration that takes one now carries a pattern), `largest_expenses` and `spend_by_category` did not say which of them answers "what did we spend the most on", and the prompt allowed a refusal to promise a later message that never comes. |
| 2026-09-14 | The digests are one workflow (`digest-tick`) rather than the planned three (`digest-tick` plus `send-weekly-digest` and `send-monthly-digest`). | The two send workflows would have differed only in which period name and which template they used, and the tick already has both in the row SQL hands it. Splitting them would have added two n8n workflows and a call boundary to carry one string each. |
| 2026-09-14 | T11 gained a tool the plan did not name: `set_digest_preference`. | R15 says a member must be able to turn their own digests off, and the scheduling side alone only proves the tick honours the column. The tool is the member's own switch: a column-level grant on `member(digest_weekly, digest_monthly)` plus a policy limiting it to their own row, so that "I'd rather not get these" can never become "I changed my own role". |
| 2026-09-13 | `v_transaction_search` gained `amount_minor` and `currency` (migration `20260913167000_search_amount.sql`). | T4 built the view without them, and R19 asks for matching transactions "with their dates and amounts", so the agent either answered half the question or spent a second tool call finishing it. The amount is the expense side of the transaction, the same side `v_period_spend` totals, so a searched figure and a reported one are the same number by construction. |
| 2026-09-13 | T10's done-when required that "the same export requested by a non-admin is refused at the database", and `tools/export_period.json` declared `hh_admin`. We changed both: an export is a member-level read. | Nothing in spec 0004 asks for the refusal. R21 says an admin *must be able to* export and does not forbid a member, and ADR 0016 with R8 already give every member the whole ledger, which A15 asserts by having a non-admin receive household-wide spending. An export is the same data in bulk, so refusing it would protect nothing that cannot already be read one question at a time, and it would need a mechanism that does not exist. |
| 2026-09-13 | Four assertions in `test-setup-conversation.sh` and `test-structural-change.sh` were rewritten. They checked `conversation.kind = 'setup'`, `conversation.step = 'accounts'` and a proposed change held in `conversation.payload`, which is the old step machine's internal state. They now assert what the requirements actually promise: the interview leaves nothing waiting (A1), asking what remains reports it and advances nothing (A38, R29), a paused exchange survives a restart with its messages intact and the next answer lands in it (A39, R0e), and a structural change is restated with nothing applied until it is agreed (A3, R0b). | The agent has no steps: what makes setup resumable is that the exchange is stored and read back (ADR 0038, ADR 0046). We also had to make A38's scenario real, because it re-triggered setup after completing it and called that "halfway", which only looked paused because the old step column reset. The test now removes the household timezone so that something genuinely remains, and restores it afterwards. |
| 2026-09-13 | `test-conveniences.sh`'s A36 assertion was rewritten. It checked that an n8n workflow with id `correction0001` had executed successfully; it now asserts the reply the member actually receives, since every outbound message is stored as a capture row, and that the reply names a real recent capture of theirs. | The assertion named the component rather than the behaviour, so deleting `correction.json` broke it even though A36's behaviour was intact. We foresaw this when T9 was split, and this is that deviation being taken. |
| 2026-09-13 | T9's "all seven spec 0003 scripts pass unchanged" bar was split into T9a, T9b and T9c, and two of those scripts were found to assert implementation detail rather than behaviour: `test-setup-conversation.sh` checks `conversation.step` values (the old step machine's internal state) and `test-conveniences.sh` checks that a workflow with id `correction0001` ran. | Migrating four workflows in one step would have left the repository broken in the middle, and the two assertions above cannot survive deleting the components they name. Each sub-task now migrates one route with everything else staying green, and we rewrite the two assertions against the behaviour spec 0003 actually requires when their own sub-task reaches them. |
| 2026-09-13 | The question-mapping prompt was built, as a prompt whose only job was turning a question into a query name, and then deleted, along with its schema, examples, stub branch and test. We replanned T6 to T11 around a single tool-calling agent (ADR 0046). | Building it made the shape visible: a fourth prompt, a fourth schema and another routing regex, on top of a capture path where a substring match in JavaScript chose the merchant instead of the agent. The mapping step also could not answer a question spanning two tools, which the loop answers without anyone anticipating it. T1 to T5, the views, the period vocabulary and the tool registry, were unaffected and stand as built. |
