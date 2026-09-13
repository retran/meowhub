---
spec: 0010
created: 2026-09-13
updated: 2026-09-13
---

# 0010 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

Two tables, one column, four views, and one question the bot asks. The whole
slice is a second reporting axis (ADR 0021) laid over a ledger that already
exists, so almost all of it is SQL — and the two rules that must not bend are
best proved by attacking them rather than by reading them back.

1. **The tables, and the invariants first.** `project`, and `planned_purchase`
   in which a **wish is the row with no target date** (the data model says so:
   there is no separate wish table). Before anything reads them, two pgTAP
   files assert what ADRs 0012 and 0021 forbid: no account belongs to a
   project, and attributing a transaction or adding a wish creates no posting.
   These are the load-bearing constraints; everything else in the slice is
   reporting.
2. **Promotion is one column.** R3's "the only difference between them" is
   literally `target_date`: promoting a wish is `update planned_purchase set
   target_date = …`, no row move and no second state machine. That makes A1 and
   A2 the same test read twice.
3. **The permission split** (R9, ADR 0021's refinement of ADR 0016): any member
   may set `transaction.project_id`; only an admin may touch an amount, a date
   or an account. An RLS policy sees a row version, not which columns a
   statement touched, so this needs the column-comparing trigger whose shape
   spec 0002 T4 already proved on `ledger_probe` — the scaffold is gone by
   then, the pattern is not.
4. **The views**: `v_project_spend`, `v_project_feasibility`, `v_wish`. Every
   figure in the slice comes from one of these, and each carries its own
   "what this includes" columns so that R17's labelling cannot be lost between
   the bot and the app.
5. **The chat surface**: the mutating half as declared tools (ADR 0039), the
   reading half as new entries in spec 0004's question mapping (R16a), and the
   belongs-to-a-project question as a gated step in the capture workflow.
6. **The screens** are spec 0006's (`docs/design/screens.md` already names
   these three views); this slice delivers the views and the queries they bind
   to, and leaves the layout alone.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| One `planned_purchase` table, a wish being the row with a null `target_date` | Promotion is a single column write; nothing to migrate between two shapes; matches the data model verbatim | The null carries meaning, so every forecast view must remember to filter on it | **chosen** — and the filter is asserted by A1 rather than trusted |
| Separate `wish` and `planned_purchase` tables, promotion copying a row | Each table's meaning is explicit in its name | Promotion becomes a move with two audit rows and an orphan to reason about; ADR 0021 calls the one-step promotion deliberate | rejected |
| `transaction.project_id` as a nullable FK on the transaction | One reference, one join, orthogonal to category exactly as ADR 0021 describes | Cannot express a shop trip split across two projects | **chosen** — the limit is ADR 0021's own, stated to the member rather than hidden (the spec's edge-case table) |
| A `transaction_project` join table, allowing several | Splitting would work later with no migration | Every spend view gains a fan-out risk and a double-count, for a case no slice can populate until transaction splitting exists | rejected — a single column is honest about what the product can do |
| Storing a project's running total on the `project` row | Cheap reads | A stored aggregate that will be stale at the worst moment, and ADR 0012's forecast is derived for exactly this reason | rejected |
| Asking the belongs-to question on every capture during an active project | Highest attribution rate | Turns capture into an interrogation, which the ergonomic budget forbids | rejected — gated by R14a's threshold and the project's own date range |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `db/migrations/` | `project`, `planned_purchase`; `transaction.project_id` and its FK; audit triggers on both new tables; grants and RLS per the classification/fact split; the column-comparing update guard | nothing planned — ADR 0021's splitting limit would be a new slice |
| `db/tests/` | The two invariant files (no money, no postings), the permission split, the view shapes, the ordering | — |
| Views | `v_project_spend`, `v_project_feasibility`, `v_wish`; `v_forecast` gains nothing but is **read** by the latter two | spec 0011 changes none of this |
| `tools/` | `wish.add`, `wish.promote`, `wish.drop`, `project.create`, `project.set_state`, `transaction.set_project` — each with its input schema and the permission it requires (ADR 0039) | — |
| `prompts/` | No new extraction prompt. The belongs-to question is a closed choice among known projects, so it is a tool call and a keyboard (ADR 0035), not a model reading free text |
| `workflows/` | The capture workflow gains one gated step after extraction and before confirmation: if an active project's range covers the capture date and the amount is above the threshold, ask — once, never twice for the same capture |
| Spec 0004's question mapping | Five new questions (R16a): a project's cost, its standing against target, whether it fits, the monthly set-aside, the wishlist in order | every later slice adds its own |
| `docs/guides/talking-to-meow.md` | Those five questions, in both languages — the list is the contract R6 of spec 0004 refuses against |
| App (spec 0006) | Screens 2 and the new Projects · Project · Wishlist screen bind to the three views | — |

## Contracts and data

- **`project`** — `id`, `name`, `state` (`idea` · `planning` · `active` ·
  `done` · `abandoned`, checked in the migration, R7), `target_amount`
  (nullable minor units + currency), `target_date_from`, `target_date_to`
  (both nullable; a single date sets both equal), `created_at`. No balance
  column, no account reference: R13 and A14.
- **`planned_purchase`** — `id`, `name`, `estimated_amount` (nullable —
  the edge case allows a wish with no amount), `currency`, `target_date`
  (**nullable; null is a wish**), `priority`, `project_id` (nullable, R4),
  `state` (`planned` · `done` · `dropped` · `postponed`, ADR 0012),
  `fulfilled_by_transaction_id` (nullable, R5 — a link, never a conversion),
  `created_by`, `created_at`.
- **`transaction.project_id`** — nullable FK to `project`. The data model lists
  `project` among the transaction's columns; the **FK lands in this slice**,
  because the referenced table does. If spec 0003 has already created the bare
  column, this migration adds only the constraint.
- **`v_project_spend`** — per project: `spent`, `planned`, `wished` as **three
  separate columns** (R17, A10 — never one sum), with per-category and
  per-period breakdowns, transfers excluded like every spend view.
- **`v_project_feasibility`** — per project with a target amount and date:
  `spent_to_date`, `target_amount`, `projected_available`, `fits` (boolean),
  `monthly_set_aside`, and `basis` — a machine-readable statement that the
  figure assumes known commitments only (R14b), so the bot and the app say the
  same thing (A7, A13) instead of each appending their own caveat.
  `fits` and `monthly_set_aside` are **null**, not false or zero, for a project
  with no target amount (A8).
- **`v_wish`** — undated `planned_purchase` rows, every member's visible to
  every member (R18), ordered by the earliest date `v_forecast` projects enough
  available cash to cover the estimate; a wish with no estimate sorts last with
  `excluded_reason` set (the edge case), and one beyond the horizon is
  `not_yet`, never impossible.
- **Tool contracts** (ADR 0039): `wish.add`, `wish.drop` and
  `transaction.set_project` require `hh_member`; `wish.promote`,
  `project.create` and `project.set_state` require `hh_admin` — promotion puts
  an item into the forecast, which is the admin act the spec's own scenario
  describes. Each fails at the database when called by the wrong member, not
  only in the tool layer.
- **The belongs-to threshold** is a household setting, not an environment
  variable (ADR 0034): it is theirs to change, defaulting to 25 € (R14a). It
  reuses whatever row-held settings mechanism spec 0003 established for the
  auto-confirm threshold rather than introducing a second one.

## Migration and compatibility

- Purely additive. No existing table changes shape except `transaction`, which
  gains one nullable column — every existing row keeps meaning exactly what it
  meant, with no project.
- Every migration has a `down`. Dropping the column drops attribution and
  nothing else: no posting, no balance and no category figure depends on it,
  which is A5 and A14 restated as a property of the schema.
- No feature flag. The slice is inert until someone creates a project, and the
  belongs-to question cannot fire before one is `active` with a range covering
  today.
- Reprocessing is unnecessary: attribution is applied going forward and by
  hand, and re-attributing later is allowed with both states in the audit log
  (the edge-case table).

## Verification strategy

Database behaviour is pgTAP, run by impersonation and by attacking the
invariant rather than reading the policy (ADR 0015). Anything conversational is
a real request through the running stack, the pattern every `scripts/test-*.sh`
already uses. Figures are compared between the bot and the view directly, never
eyeballed.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | pgTAP: snapshot `v_forecast` in full, add a wish with no target date, snapshot again — asserted identical row for row |
| A2 | The same file: set `target_date`, assert the item now appears in `v_forecast` on that date and nowhere else |
| A3 | pgTAP: close a wish against an existing transaction; assert `fulfilled_by_transaction_id` is set and `count(*)` over `transaction` and `posting` is unchanged |
| A4 | pgTAP fixture — three categories, two months, one project; assert `v_project_spend.spent` equals the sum of those transactions and that both breakdowns reproduce it |
| A5 | The same fixture: snapshot `v_category_spend` before and after attribution, asserted equal — project attribution moves no category figure |
| A6 | pgTAP by impersonation: `hh_member` sets `project_id` on another member's transaction and succeeds; the same role updates an amount and fails at the guard |
| A7 | pgTAP with a fixed balance-and-commitment fixture and a 3 000 € target in March: assert `fits`, `monthly_set_aside` and a non-empty `basis` naming the known-commitments-only assumption |
| A8 | pgTAP: project with `target_amount` null — `spent` present, `fits` and `monthly_set_aside` **null**, asserted null rather than falsy |
| A9 | `scripts/test-project-question.sh`: drive a capture above the threshold inside an active project's range; assert the question was asked once, the answer honoured, and — the half that matters — that leaving it unanswered leaves `project_id` null. A second capture below the threshold asserts no question at all |
| A10 | pgTAP asserts the three columns exist separately and are never summed in the view; the chat rendering is asserted in A16's script and the app's in a Playwright journey against the Projects screen |
| A11 | pgTAP against a fixed forecast fixture: assert the ordering, that an unestimated wish sorts last with `excluded_reason`, and that an unaffordable one is `not_yet` rather than absent |
| A12 | pgTAP: set the project `done`; assert its report still returns and is unchanged by subsequent reads |
| A13 | `scripts/test-project-figures-agree.sh`: each of R16a's five questions asked through the bot and queried from the view directly, diffed — the same shape spec 0004 establishes for every figure |
| A14 | pgTAP: assert no `account` row references a project and that attributing a transaction produces zero new `posting` rows — the ADR 0012/0021 invariant, attacked directly |
| A15 | pgTAP by impersonation: wish written as the non-admin member, read back as the other member and as an admin |
| A16 | The A13 script asserts each of the five answers arrives, in the member's language, with its spent/planned/wished labelling intact |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The belongs-to question turns capture into an interrogation, and people stop capturing | medium | R14a's threshold, the active-project-and-range window, and at most one question per capture — all three asserted by A9's negative half, which is the test that actually protects the habit |
| A project's total is only as good as people's tagging, and a partial total reads as a complete one | high | R17's three separate columns everywhere, so an under-attributed project shows a small `spent` rather than a confident wrong total; plus the inline project picker on the confirmation queue, where attribution is a tap |
| `v_forecast`'s default horizon (end of next month, spec 0009 R18) is shorter than most project target dates | high | `v_project_feasibility` extends the horizon to the target date; where the commitment data does not reach that far, `basis` says so rather than the view implying certainty |
| Two overlapping active projects make the question a menu | low | The question offers both and never guesses (the edge case); ADR 0035 caps the keyboard at a handful and the typed equivalent always works |
| The classification/fact permission split drifts from ADR 0016's simpler rule as later slices add columns | medium | The guard compares columns rather than enumerating them by role, and A6 is a standing negative test rather than a one-off check |

## ADRs required

None. ADR 0021 already decided the structure — the second axis, the single
project reference, the wish-is-an-undated-plan promotion and the
classification-versus-fact split — and ADR 0012 decided that none of it becomes
a posting. This plan implements those decisions rather than making new ones.

The one decision that would need an ADR is the one the spec deliberately keeps
out of scope: splitting a transaction across two projects, which ADR 0021
records as a known limit and which would change `transaction.project_id` into a
join table.
