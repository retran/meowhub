---
spec: 0003
created: 2026-09-13
updated: 2026-09-13
---

# 0003 - Tasks

Work the tasks in order: start one only once its dependencies are closed. Each
task is one logical commit that leaves the project in a working state.

Legend: `[ ]` not started, `[~]` in progress, `[x]` done, `[-]` dropped.

## Tasks

- [x] **T1.** The ledger schema: `account`, `account_term`, `transaction`,
      `posting`, `merchant`, `merchant_alias`, `translation`,
      `household_setting`, `member.default_payment_account_id`. Four
      amendments to `docs/architecture/data-model.md` land in the same
      commit, before the migration that needs them: `capture` becomes one
      row per message, `transaction` gains `original_amount`/
      `original_currency`, `account` gains `reviewed`, and
      `household_setting` is new. The same migration drops `ledger_probe`,
      the scaffold from spec 0002 T4.
  - Depends on: none
  - Requirements: R1, R3, R4, R11b, R28, R0d
  - Done when: the migration applies and reverses cleanly; `ledger_probe`
      no longer exists; pgTAP confirms every new table's shape against the
      amended catalogue.

- [x] **T2.** The invariant: postings sum to zero per transaction, enforced
      by a deferred constraint trigger and attacked directly before any
      workflow exists. Audit triggers go on every new table.
  - Depends on: T1
  - Requirements: R2, R7, R22
  - Done when: A6 (an unbalanced multi-row write is rejected at commit,
      inserted directly) and A30 (a write with no acting member fails,
      under each writing role) both pass in pgTAP against
      `test-ledger-invariant.sh`. A5 needs `v_period_spend`, so T5 proves
      it once that view exists.

- [x] **T3.** Row-level security on every new table, in the shape spec
      0002 already proved on `ledger_probe`: `hh_agent` inserts what it
      captures; any member reclassifies; a member confirms or corrects
      only their own unconfirmed row; only an admin corrects a financial
      fact or deletes.
  - Depends on: T2
  - Requirements: R15 (spec 0002), R10, R15a (this spec)
  - Done when: A17 (a non-admin's `delete` on `transaction` fails,
      impersonated) passes, and the grant table matches R15b's shape for
      every new table.

- [x] **T4.** `conversation`, `capture` (one row per message) and
      `correction_request`. `capture.conversation_id` and `.sequence`
      order the exchange, and `direction` distinguishes an inbound message
      from the agent's own outbound question.
  - Depends on: T3
  - Requirements: R0e, R6a, R16a, ADR 0038
  - Done when: pgTAP proves a multi-row `capture` exchange orders by
      `sequence`, and that `conversation` state survives being read back
      after a fresh connection, which is the shape ADR 0038 requires and
      is proven structurally here; A39 proves it end to end once the
      workflows exist.

- [x] **T5.** The views this slice needs, every one
      `WITH (security_invoker = true)`: `v_account`, `v_account_balance`,
      `v_category`, `v_period_spend`, `v_transaction_detail`,
      `v_unconfirmed`, `v_unconfirmed_summary`.
  - Depends on: T4
  - Requirements: R5, R11b, R22, and ADR 0040's rule that nothing computes
      a figure outside a view
  - Done when: pgTAP impersonation proves each view respects RLS (reading
      as `hh_member` never returns a row `hh_member` could not reach
      directly); A27 (a category's display name follows the reading
      member's language) passes; and A5 (a cash withdrawal is a transfer
      that leaves `v_period_spend` unchanged for the month, and spending
      the cash is what moves it) passes against the real view.

- [x] **T6.** The real seed: the starter chart and categories in both
      languages, opening balances, and several months of transactions
      including a card settlement, a cash-advance fee and a loan-payment
      split.
  - Depends on: T5
  - Requirements: ADR 0015
  - Done when: `task seed` loads cleanly against the new schema and every
      view in T5 returns non-trivial data from it.

- [x] **T7.** Prompts and tools as files: `prompts/capture-text/` (system
      prompt, output schema, examples, version, in both languages) and
      the tool declarations in `tools/` this slice needs, which are
      `record`, `correct`, `confirm`, `classify`, `delete`, `open_account`,
      `amend_account`, `merge_category` and `undo`, each naming its
      permission and its ADR 0042 shape (`composes` or `acts_as`). The
      startup check refuses to run without them.
  - Depends on: T6
  - Requirements: R11c, R11cc, R11d, ADR 0025, ADR 0039, ADR 0042
  - Done when: A29 (a prompt file removed from the mount fails the
      container's startup, not the first capture) passes.

- [x] **T8.** The capture-text workflow: the entry point
      (`telegram-normalize-and-dispatch`) gains one step, loading the
      member's open conversation, then dispatches to a new
      `capture-text` workflow. It covers merchant recognition, category
      classification with the merchant's own default preferred over a
      model call, defaults for account and date, the balanced write
      through `hh_agent` (ADR 0042), and the one-line confirmation reply.
  - Depends on: T7
  - Requirements: R8, R9, R10, R11, R11a, R12, R13, R14, R18, R19
  - Done when: A7, A8, A9, A10, A11, A12, A23, A23a, A24, A26, A34, A37 all
      pass in `test-capture-text.sh` against the real (stubbed) model
      gateway; A21 (an unlinked Telegram id produces no transaction, which
      is spec 0002 T12's own gate extended here with that assertion) and
      A22 (`scripts/test-telegram-dedup.sh` extended: the same update
      delivered twice produces exactly one transaction) both pass.

- [x] **T9.** Unparsed captures and the multi-question agent: no
      recoverable amount, a follow-up question when an answer still
      leaves a gap, never the same question twice, every message stored
      in order, and the exchange resuming on the next message.
  - Depends on: T8
  - Requirements: R17
  - Done when: A18, A18a, A19, A20, A28, A31, A40, A41 all pass,
      including the scripted multi-turn replay (A40) and the schema-
      violation and gateway-failure cases (A20, A28).

- [x] **T10.** The setup conversation: the agent asks for accounts,
      opening balances, default payment accounts, cash handling, timezone
      and default currency, one question at a time, resumable, and useful
      after the first account. It restates a structural change (open,
      rename, deactivate or re-term an account; rename, re-parent or merge
      a category) before applying it, and mints each one as the asking
      admin's own role (ADR 0042) rather than the agent's.
  - Depends on: T9
  - Requirements: R0, R0a, R0b, R0c, R0d, R0e, R0f, R29
  - Done when: A1, A2, A3, A4, A38, A39 all pass, with A39 proven by
      restarting n8n and postgres mid-conversation and asserting it
      resumes at the same step, which is what proves ADR 0038 rather than
      merely asserting it.

- [x] **T11.** Corrections and the request path: an admin corrects amount,
      date, category, merchant or account in one message; a non-admin's
      same message becomes a `correction_request` with the admins
      notified; any member reclassifies or reprojects unconditionally; an
      admin deletes.
  - Depends on: T10
  - Requirements: R15, R15a, R16, R16a, R7b, R7c (the confirm half; the
      quiet-period rule is T12)
  - Done when: A13, A14, A15, A16 pass in `test-corrections.sh`, each
      minted as the acting member's own role (ADR 0042) so that A17's
      refusal comes from the database and not from the workflow.

- [x] **T12.** `auto-confirm-quiet`, the one scheduled workflow: a known
      merchant, the merchant's own category, an amount below the
      configured threshold and a wait past the configured quiet period
      together mean the transaction is confirmed with its route recorded.
      It runs from the scheduler container like every other job.
  - Depends on: T11
  - Requirements: R7a, R7c
  - Done when: A25 passes, run directly the way cron would invoke it,
      the same pattern spec 0001's drift check and spec 0002's digest
      jobs already use.

- [x] **T13.** The conveniences: inline buttons with a typed equivalent
      for every action, "undo" as a compensating change, a free-text note
      on a transaction, "как обычно" and "same again", the recent-captures
      list, "what still needs setting up", and the agent's own memory
      (ADR 0044), which means the `remember` tool and reading relevant
      memory when composing a reply.
  - Depends on: T12
  - Requirements: R23, R24, R25, R25a, R26, R27, R29
  - Done when: A32, A33, A34 (note), A34a (memory), A35, A36 all pass in
      `test-conveniences.sh`.

- [x] **T14.** Chat administration of the unconfirmed queue, and the
      declared-tool negative tests across the whole surface built by T7 to
      T13.
  - Depends on: T13
  - Requirements: R20, R11cc
  - Done when: A43, the admin-facing counterpart of A20, passes by listing
      and confirming the queue in chat, and A42 passes for every tool
      declared in T7: malformed input writes nothing, and a member without
      the permission fails at the database.

- [x] **T15.** The golden set's first run, and documentation:
      `docs/guides/household-setup.md` (what the setup conversation asks
      and why) and `docs/guides/talking-to-meow.md` (what a member can
      say, in both languages).
  - Depends on: T14
  - Requirements: ADR 0025
  - Done when: the golden set runs against a real model (not the stub,
      and not part of `task test`) and its scores are recorded in this
      commit; both guides exist and are linked from
      `docs/guides/local-development.md`.

## Deviation log

Where the work had to depart from the plan, record here what changed and why,
and fix the spec or the plan to match.

| Date | What changed | Why |
|---|---|---|
