---
spec: 0004
created: 2026-09-13
updated: 2026-09-13
---

# 0004 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

Bottom-up, as in specs 0001–0003: the figures exist and are proven correct
before anything can ask for them, and no criterion is closed by reading a
workflow back.

1. **The views first** — the reporting half of `docs/architecture/data-model.md`,
   in migrations, with their signatures snapshotted. They are testable in pgTAP
   against the seeded household on the day they land, with no model, no workflow
   and no bot involved. This is the whole contract: everything above is wiring.
2. **The period vocabulary** (ADR 0045). "For a period" is answered from a fixed
   enumeration resolved to dates **in SQL**, in the household's timezone. Every
   spend view carries the period name as a column, so a question is a filter
   rather than a date calculation, and the previous period's figure is a column
   of the same row (R18) rather than a second call and a subtraction (R4).
3. **The read tools** — one declared tool per answerable question, in spec 0003's
   registry format (ADR 0039). Adding a view in a later slice means adding a tool
   here, which is what makes R2a mechanically checkable rather than a promise.
4. **The agent loop** (ADR 0046) replaces what specs 0001–0003 built as a router,
   a prompt per task and a workflow per task. One system prompt, one loop, and a
   dispatcher that executes tool calls:

   ```
   messages = [system, ...recent history, user message]
   for round in 1..MAX_ROUNDS:
       response = model(messages, tools)
       if response has tool_calls:
           for each call: execute it, append its result
           continue
       reply = response.content; break
   else:
       degrade to the unparsed path
   ```

   The model chooses which tools to call. The **executor** mints the token for
   the acting identity (ADR 0042) — the agent naming `delete_transaction` is a
   request, not an authorisation, and a member who may not delete is refused by
   the database exactly as before. The loop is bounded; an exhausted budget, a
   failing tool or an unreachable gateway degrades to a stored message and an
   honest sentence, never to a guess.
5. **The agent writes the reply**, in the member's language, following the
   persona. What replaces a template's guarantee is a property: every figure in
   the reply appears in a tool result from that same exchange, and no figure
   appears that does not (R4a, A14). That check is the one this slice cannot do
   without.
6. **The digests** stay model-free: SQL and a template, on their own schedule,
   reading the same views — so R13's "can never disagree" is true by
   construction. A digest is a broadcast, not a conversation: it must be
   reproducible and free of commentary by construction (R12, A12), which is
   exactly what a committed template gives and an agent's own words do not.
7. **Search, "why this category" and CSV export** are tools like any other. They
   need no separate workflow and no trigger phrase: the agent calls them when a
   member asks something they answer.

## What this replaces

Specs 0001–0003 shipped four things this slice deletes rather than extends. They
are listed here because the deletion is work, and because a half-migrated agent
is worse than either shape:

| Built in 0003 | What happens to it |
|---|---|
| `workflows/capture-text.json` — one model call, then merchant/category/account resolution in JavaScript | The extraction becomes the agent's own judgement, and the resolution becomes tools it calls (`find_merchant`, `create_merchant`, `find_category`, `create_category`, `find_account`). The workflow goes |
| `workflows/setup-conversation.json` — its own prompt, schema and step machine | Setup is a conversation the agent has with the tools it already needs (`open_account`, `amend_account`, `record_transaction`). The prompt and the step machine go |
| `workflows/structural-change.json`, `workflows/correction.json` — regex intent parsing | The agent understands the intent; the tools apply it. Both workflows go |
| `Route Message`'s trigger-phrase regexes in the dispatch workflow | One conversational entry point, one agent. The regexes go |

Every behaviour those workflows implement is a requirement of spec 0003 and stays
true — a spec describes behaviour, not implementation, so 0003's requirements and
acceptance criteria are unchanged and its tests keep passing. What changes is
which component satisfies them, which is this document's business.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Fixed period vocabulary resolved in SQL, carried as a column on every spend view | One call per question; the previous period is a column so R18 cannot be forgotten; no date arithmetic outside the database | An unusual range is a refusal until a period is added, and adding one is a migration | **chosen** (ADR 0045) |
| Views parameterised by arbitrary `from`/`to` as PostgREST RPC functions | Any range answerable | The agent has to produce dates, and it puts aggregation in functions while the catalogue calls them views | rejected |
| Compute the period-over-period delta in the workflow from two calls | No new columns | Arithmetic on money outside the database, which R4 forbids and ADR 0040 calls a defect | rejected |
| One agent, one prompt, a bounded tool-calling loop | Answers combinations nobody anticipated; merchant and category choice move to the participant with the context; four prompts and three workflows collapse into one | The figure guarantee becomes a tested property rather than a structural impossibility; more tokens per exchange | **chosen** (ADR 0046) |
| A mapping model that picks one tool, then a templated answer | The model structurally cannot emit a number | Cannot answer a compound question, cannot choose a merchant, and every new question shape costs a prompt, a schema, examples and two catalogue strings | rejected |
| Let the agent write SQL against a read-only role | Answers anything | Un-reviewable, unbounded, and it makes R6's refusal undefinable — there is no declared set to be outside of | rejected |
| n8n's own schedule trigger with a cron expression for the digests | Simplest wiring | The cron expression cannot know the household's timezone, which is a database row (ADR 0034), and a container down at 09:00 silently skips the week | rejected |
| Hourly tick; SQL decides whether a digest is due and unsent | The timezone stays where it belongs; a missed hour self-heals; idempotent by construction | One cheap query per hour, and "sent" becomes state to keep | **chosen** |
| Digests written by the agent for nicer prose | — | R12 forbids commentary, and a digest that is generated rather than templated can disagree with an answer | rejected |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `db/migrations/` | The reporting views, the period dimension (ADR 0045), `digest_run`, digest preference columns on `member`, the search index | 0007 adds reconciliation to `v_period_reconciliation`; 0008–0010 add their own views and tools |
| `db/tests/` | View signature snapshots, per-view figure tests, `security_invoker` impersonation tests | every slice that adds a view |
| `tools/` | The read tools, plus the lookup tools the agent needs to choose rather than be handed a choice: `find_merchant`, `create_merchant`, `find_category`, `create_category`, `find_account` | R2a: every later slice adds its own |
| `prompts/agent/` | The one system prompt (ADR 0046), replacing `prompts/capture-text/` and `prompts/setup-conversation/` | grows with the persona, not with the task list |
| `workflows/` | `agent` (the loop) and `digest-tick` / `send-weekly-digest` / `send-monthly-digest`. `capture-text`, `setup-conversation`, `structural-change` and `correction` are deleted | later slices add tools, not workflows |
| `i18n/` | Digest templates, the "no data" line, and the failure vocabulary — what the system says *without* the agent | every slice |
| `docs/guides/talking-to-meow.md` | The documented list of answerable questions (R23) | every slice that adds a question |
| `docs/architecture/data-model.md` | `member` gains digest preferences; `v_reporting_period` and the spend-view family | as views are added |

## Contracts and data

- **Views.** `v_period_spend`, `v_category_spend`, `v_category_spend_by_month`,
  `v_merchant_spend`, `v_merchant_spend_by_month`, `v_member_spend`,
  `v_member_spend_by_month`, `v_category`, `v_account`, `v_account_balance`,
  `v_liability_summary`, `v_household_position`, `v_unconfirmed`,
  `v_unconfirmed_summary`, `v_transaction_detail`, `v_transaction_search`,
  `v_period_reconciliation`, `v_reporting_period` — names and meanings fixed by
  `data-model.md`.
- **Every spend view** carries: the grouping key, `period`, `period_start`,
  `period_end`, `amount_minor`, `previous_amount_minor`, `delta_minor`,
  `unconfirmed_amount_minor`, `unconfirmed_share`. Transfers are excluded in the
  view, never by the caller.
- **Every view is created `WITH (security_invoker = true)`**, so the caller's
  row-level security applies rather than the view owner's. A view without it is
  the rank-1 failure in ADR 0015's table, so it is asserted by impersonation.
- **Tool declaration** (spec 0003's registry format): `name`, `purpose` naming
  the view it reads, `shape`, `permission`, `mutating`, and a JSON Schema for
  parameters. The registry is both the answerable set and the agent's tool list —
  the loop builds the model's `tools` array from these files, so a tool that
  exists is a tool the agent can call, with no second list to keep in step.
- **Tool executor**: one dispatcher, `name → (parameters, acting identity) →
  PostgREST call → rows`. It mints the token per ADR 0042 and returns the rows
  verbatim; it never reformats a figure, because a figure the executor touched is
  a figure the database no longer vouches for.
- **`digest_run(member_id, kind, period_start, sent_at)`** — scheduling
  bookkeeping, deliberately *not* a view and not in the catalogue: it is not a
  figure about money.
- **`member.digest_weekly`, `member.digest_monthly`** (boolean, default true) —
  R15.

## Migration and compatibility

- Additive only in the database: no table spec 0003 created is reshaped, and
  every migration has a `down`.
- The agent loop is built and proven **beside** the existing workflows, then they
  are deleted in one task once their own acceptance criteria pass through it.
  Spec 0003's test scripts are the migration's own safety net: they drive real
  messages through the real dispatch and assert database outcomes, so they pass
  unchanged if and only if the behaviour survived the move.
- `v_period_reconciliation` exists from this slice but reports "not reconciled"
  everywhere until spec 0007 gives it something to read — stated in the answer,
  never omitted (R17).
- Search uses `unaccent` and `pg_trgm` over note, merchant and capture text
  rather than a per-language stemmer: a transaction does not record which
  language it was written in, the household writes in two and mixes them, and
  merchant names are neither language.
- The seeded household is the fixture for every figure test; no real household
  data is committed (ADR 0015).

## Verification strategy

Figures are pgTAP against the seeded household: the view is compared with an
independent aggregation written in the test, never with itself. Everything above
the database is a real request through the running stack with the model gateway
stubbed (ADR 0015) — and the stub now answers with **tool calls**, not with a
finished extraction, because that is what the real model returns. Digest
scheduling is tested by moving the clock in SQL, not by waiting.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | `scripts/test-answer-question.sh`: assert the reply carries the figure, the named period and the unconfirmed share |
| A1a | Same script, ranked question: assert the reply lists categories in descending order with each total, matching `v_category_spend` ordered by amount |
| A2 | The same question from a Russian-language member: assert the figure is identical and the reply is in Russian |
| A3 | A question no tool answers: assert no figure in the reply and that it names what can be asked |
| A4 | `scripts/test-view-figures.sh`: for each read tool, run it and query its view directly with `psql`; assert equality |
| A5 | pgTAP: `v_account_balance.balance` equals the independent sum of that account's postings |
| A5a | pgTAP plus the answer script: holdings, liabilities, net position and headroom each answered from their view; assert the headroom reply names the limit it is measured against |
| A5b | `scripts/test-answerable-questions.sh`: every view has a read tool or a committed exemption, and `talking-to-meow.md` matches the registry exactly |
| A6 | pgTAP: seed a period with a known unconfirmed mix; assert `unconfirmed_share` exactly; then assert the rendered answer states it |
| A7 | `scripts/test-digest.sh`: run the tick at Monday 09:00 household time; assert one digest per member with digests enabled, each in that member's language |
| A8 | Same script: render the weekly digest and ask the equivalent questions; assert every figure matches, from the same view |
| A9 | Same script with `digest_weekly = false`: assert no message and no `digest_run` row |
| A10 | Same script against an empty period (the closed month, which the seeded household has nothing in): assert a message is sent and is the catalogue's single "nothing recorded" line |
| A11 | `scripts/test-digest-heartbeat.sh`: prevent the digest, let the Kuma window pass, assert the alert |
| A12 | `scripts/test-digest-language.sh`: the digest **templates themselves** are checked against a committed list of forbidden accounting and judgement words, so a new string cannot smuggle one in |
| A13 | Point the gateway stub at a failure: assert the reply is the catalogue's plain failure line, contains no digits, and nothing is recorded as an answer |
| A14 | `scripts/test-figure-traceability.sh`: capture the tool results and the reply for each golden question; assert every number in the reply appears in a tool result, and that no number in the reply appears in none of them |
| A15 | The full answer path as a `hh_member` session: assert household-wide spending is returned (ADR 0016) |
| A16 | `scripts/test-digest.sh` with the clock at Monday 08:59, 09:00, 09:01 and the 1st: assert exactly one weekly and one monthly send, neither waiting on reconciliation, each stating the period's reconciliation status |
| A17 | The figure test (A4) asserts the reported previous-period value equals `previous_amount_minor`; the traceability test (A14) asserts it is present in the reply |
| A18 | pgTAP over `v_transaction_search` with a seeded note, plus `scripts/test-search-why-export.sh` end to end: assert the transaction is returned by a word from its note, with its amount |
| A19 | pgTAP on `v_transaction_detail`, plus `scripts/test-search-why-export.sh`: the agent's reply names the model and prompt version in the model case and says "merchant default" — naming no model — in the other |
| A20 | `scripts/test-search-why-export.sh`: export the period and assert the CSV's expense total equals `v_period_spend` for it, that records end CRLF and a note carrying a comma and a quote survives the round trip, so it opens in a spreadsheet without repair |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The agent reports a figure the database never returned — a transcription slip, or a percentage it computed itself | medium | A14's traceability check is a hard gate on every golden question, and the persona prompt forbids deriving a figure. This is the risk the templated design did not have, and it is the price ADR 0046 names |
| The agent calls a tool it should not, or with the wrong member's authority | low | The executor, not the model, mints the token (ADR 0042); every guard and policy from spec 0003 is unchanged and is tested by impersonation, not through the bot |
| The loop runs away on a model that calls tools badly | medium | A hard round cap per message, then the unparsed path. Asserted by a test that stubs an always-calls-a-tool model |
| A view is created without `security_invoker` and silently reads past row-level security | medium | Asserted by impersonation for every view, generated from the catalogue so a new view cannot be added without one |
| One prompt for every job regresses capture while improving questions | medium | The golden set covers both, and a regression in extracted numbers or chosen accounts blocks the change (ADR 0025) |
| Migrating 0003's paths onto the loop loses a behaviour nobody notices | medium | 0003's own test scripts are unchanged and must pass through the loop before its workflows are deleted; the deletion is its own task, after the proof |
| Digest and answer drift apart as views change | low | They read the same views; A8 compares them every run |
| The hourly tick double-sends after a restart | low | `digest_run` is unique on `(member_id, kind, period_start)`; the insert is the send's gate, not its record |

## ADRs required

- **ADR 0045 — reporting periods are a fixed vocabulary resolved in SQL.**
  Accepted with this slice's T1.
- **ADR 0046 — the agent is one tool-calling loop that writes its own replies.**
  Accepted; it amends ADR 0017 (the catalogue's scope), ADR 0025 (one prompt, not
  one per task), ADR 0029 (the routing table's mapping row, and what the model is
  allowed to see) and ADR 0040 (the conversational workflows collapse into one).
- No new ADR for `security_invoker`: it is a schema rule, and it belongs in
  `data-model.md`'s Rules section.
