---
spec: 0007
created: 2026-09-13
updated: 2026-09-13
---

# 0007 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

Two mechanisms, kept apart on purpose: **parsing is a pure function outside the
database, reconciliation is a function inside it.**

1. **Fixtures first (R25).** One real export per provider and format, anonymised
   by a committed script, and the raw originals never enter the repository.
   Nothing else in this slice starts until they exist — a parser written against
   a format's documentation is a parser written against a fiction.
2. **`statement-parser`**, a new container in the same shape as `token-bridge`:
   given bytes and a declared format, it returns normalised lines, the file's
   stated closing balance or total, and its own provenance. It reads no database
   and writes nothing, which is what lets ADR 0015's rank-3 tests run it as a
   pure function over committed fixtures with no stack around it.
3. **Parsers in the order the household needs them**: CAMT.053 (both banks'
   preferred export), then the ICS card CSV, then MT940 for historical files,
   then XLS — which is converted to CSV at the parser's edge, so R4's "treated as
   CSV" is literal and there is one CSV code path, not two.
4. **Staging, then preview, then apply, then reverse.** An upload stores the file
   (ADR 0019, already built), records a `statement_import` and its
   `statement_line` rows in state `previewed`, and stops. `v_reconciliation_preview`
   then says what applying would do, reading only. `apply_statement_import()` is
   one SQL function in one transaction: validate, match, create, supersede, flag,
   confirm — or raise and write nothing. `reverse_statement_import()` undoes the
   same unit.
5. **The PDF path last**, because it is the fallback (ADR 0013) and everything it
   produces is provisional. It reuses the same staging and apply path; only the
   parser differs and the lines are marked model-derived.
6. **The review screen and the monthly-routine guide**, which are what make the
   flagged queue drainable by the admin who did not build any of this.

Matching and application live in SQL rather than in n8n for one reason that
decides it: the spec requires an import to be applied atomically or not at all,
and a workflow making many HTTP calls to PostgREST cannot be. In the database it
is one transaction for free, arithmetic stays out of workflows (ADR 0040), and
every negative case is pgTAP-testable by impersonation (ADR 0015, rank 1 and 3).

**On A12's "nothing is written".** A preview writes no *ledger* row — no
transaction, no posting, no confirmation, no merchant. It does write the
`statement_import` and its staged `statement_line` rows, because a preview is the
record of an upload and an import abandoned at preview must stay visible and
disposable rather than vanish. The plan reads the criterion as being about the
books, which is what it is protecting; if the household means it literally, the
spec is what changes.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Parsers as a separate stateless service, reconciliation as SQL functions | Parsers test as pure functions over fixtures with no stack; apply is atomic by construction; RLS is the only gate | One more container, and a second language in the repository | **chosen** |
| Parse inside n8n Code nodes | No new container | CAMT.053 XML and XLS in a Code node is product logic in wiring (ADR 0040), untestable as a pure function, and the parser becomes something only n8n can run | rejected |
| Parse in PostgreSQL (`xmlparse`, `COPY` for CSV) | One place, atomic end to end | Hostile for XLS and for the model path; fixtures become database fixtures; a parser bug becomes a migration | rejected |
| Match and apply in n8n against PostgREST | Visible as a flow | Cannot be atomic across many calls — the one thing the spec's own edge case table forbids | rejected |
| `security definer` apply/reverse functions | Simpler grants | Makes the function a softer gate than row-level security, exactly what ADR 0039 warns against; A16 must fail at the database, not in a check we wrote | rejected — invoker, gated by RLS |
| One parser per provider rather than per format | Matches how files are downloaded | Two banks exporting the same CAMT.053 would get two parsers that drift; dialect differences belong in fixtures, not in duplicate code | rejected |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `statement-parser/` | New service: CAMT.053, CSV (and XLS via CSV), MT940, and the PDF path's model call. Stateless, no database access | a new provider or format |
| `statement-parser/fixtures/` | One anonymised fixture per format, each with its expected normalised lines | every format added later |
| `db/migrations/` | `statement_import`, `statement_line`; `account` gains the per-account match tolerance and settlement rule; `apply_statement_import()`, `reverse_statement_import()`; `v_statement_import`, `v_statement_line`, `v_reconciliation_preview`, `v_period_reconciliation` | spec 0009 reuses the matching machinery for commitments |
| `db/tests/` | pgTAP for matching, supersession, atomicity, reversal, and the admin-only negative case | — |
| `workflows/` | `import-statement`: take the upload, store the file, call the parser, stage, reply with the preview; `apply-statement-import` and `reverse-statement-import` as the admin's confirmations (ADR 0040) | — |
| `prompts/` · `tools/` | The PDF statement prompt and its strict schema (ADR 0025); the import, apply and reverse tool declarations (ADR 0039) | — |
| `app/` | The reconciliation review screen — spec 0006 names it as arriving here, with that slice's design system and keyboard model | — |
| `scripts/` | `anonymise-statement.sh`; `test-statement-parsers.sh`; `test-statement-import.sh` | — |
| `docs/guides/monthly-routine.md` | New: three downloads, three uploads, what to do with what it flags | spec 0008 |
| `docs/architecture/data-model.md` | The two new entities and four views, plus the `account` columns below | every slice that adds a view |

## Contracts and data

- **`statement_import`** — `account_id`, `file_id`, `format`, `period_start`,
  `period_end`, `stated_closing_balance` (nullable), `validation` (one of
  `closing_balance`, `stated_total`, `settlement_agreement`, `override`),
  `state` (`previewed`, `applied`, `reversed`, `rejected`), `applied_by`,
  `applied_at`, `reversed_by`, `reversed_at`, counts of created, matched,
  superseded and flagged.
- **`statement_line`** — `import_id`, `booking_date`, `value_date`, `amount`
  (signed minor units), `currency`, `original_amount` and `original_currency`
  (R28), `provider_reference`, `descriptor` kept raw, counterparty name and IBAN
  where the format carries them, `provenance` (`parser` or `model`, with the
  parser name or the model and prompt version), `provisional`, `match_state`
  (`unmatched`, `matched`, `ambiguous`, `duplicate`, `superseded`),
  `transaction_id`.
- **`account` gains** `match_tolerance_days` (default 5, R15b),
  `settlement_counterparty_iban` and `settlement_descriptor_pattern` (R15a) —
  household settings, so database rows rather than environment (ADR 0034).
  `docs/architecture/data-model.md` is extended before the migration lands, per
  its own rule that a spec naming something the catalogue lacks is incomplete.
- **`transaction`** already carries its import and its confirmation route in the
  catalogue; R14's "attributed to the import rather than to a member" and R13's
  bank route are those columns, not new ones.
- **`apply_statement_import(import_id) returns import_result`** — validates
  first and raises on failure, so a rejected import applies nothing (R9, A7).
  `security invoker`: a member calling it fails at the database (R23, A16).
- **`reverse_statement_import(import_id)`** — removes every transaction the
  import created, withdraws every confirmation it granted, restores superseded
  lines, and leaves the audit trail (R22, A13).
- **The parser's contract** — `POST /parse` with the bytes and a declared format,
  answering normalised lines plus the file's stated closing balance or total and
  the provenance to record. No database, no state, nothing cached. A file it
  cannot parse is a plain refusal, never a partial line set.
- **Views**: `v_statement_import`, `v_statement_line`,
  `v_reconciliation_preview` (created, matched, superseded, flagged, per line,
  written nowhere), `v_period_reconciliation` (per account and period, read by
  the app, the digests and the home screen).

## Migration and compatibility

- **Nothing to migrate.** Both tables are new, and the `account` columns are
  additive with defaults, so existing rows keep working.
- **Spec 0003's ledger is the dependency**, not a thing this slice changes:
  `transaction`, `posting`, `merchant`, `merchant_alias` and the confirmation
  state all exist before this starts.
- **Reversible by design, twice over**: every migration has a `down`, and an
  applied import is reversible in the product itself, which is the stronger
  guarantee and the one the household will actually use.
- **The provisional-to-authoritative upgrade is the one destructive path.**
  Supersession removes the transactions a PDF import created within the same
  atomic apply that creates the structured ones, so a failure leaves neither.
- **No fixture is a real statement.** Raw downloads live in `.data/`, already
  gitignored, and only the output of `anonymise-statement.sh` is ever committed.

## Verification strategy

Parsers are pure functions over committed fixtures (ADR 0015): the tests POST
fixture bytes at the parser and compare normalised lines against a committed
`expected.json`, with no database and no n8n involved. Matching, application,
reversal and every permission case are pgTAP against a real PostgreSQL, by
impersonation. Only the criteria that are genuinely about the whole path run end
to end through n8n and PostgREST.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | `db/tests/*_statement_apply.sql`: the CAMT.053 fixture staged and applied against the seeded household; assert every line has its reference and `v_account_balance` equals the fixture's stated closing balance |
| A2 | pgTAP: apply the same fixture twice; assert the second run writes no transaction and records `duplicate`, keyed on the provider reference and the file's content hash |
| A3 | pgTAP over the ICS CSV fixture: every created posting hits the card liability; assert no posting touches any asset account |
| A4 | pgTAP: a bank fixture containing the ICS settlement; assert a transfer, the liability falling, and `v_period_spend` unchanged before and after |
| A5 | pgTAP: seed a hand-captured expense, apply the matching fixture line; assert one transaction, `confirmed`, route `bank` |
| A6 | pgTAP: a fixture line with no counterpart; assert a confirmed transaction attributed to the import and to no member |
| A7 | pgTAP: a fixture mutated so its lines miss the closing balance; assert `apply_statement_import` raises, the discrepancy is reported, and no ledger row exists afterwards |
| A7a | pgTAP over the unmodified ICS CSV fixture: assert it validates on its stated total, `validation = 'stated_total'`, and `validation <> 'override'` — the assertion that an override on the monthly path is a defect |
| A8 | pgTAP: the A7 fixture applied with an explicit override; assert it applies and the override is recorded with its actor |
| A9 | `scripts/test-statement-parsers.sh` against the PDF fixture with the model stubbed; assert every line `provisional` and `provenance = 'model'` with the prompt version |
| A10 | pgTAP: apply the PDF fixture, then the CAMT.053 fixture for the same account and period; assert the provisional lines are superseded, their transactions gone, no duplicates, and balances those of the structured file |
| A11 | pgTAP: a fixture line recognised as overdraft interest; assert the posting lands on the interest expense account and on no spending category |
| A12 | pgTAP: read `v_reconciliation_preview` for a staged import; assert the four counts, and assert zero rows in `transaction`, `posting` and `merchant` written since staging |
| A13 | pgTAP: apply then reverse; assert balances equal their pre-import values row for row, confirmations granted by the import are withdrawn, and `audit_log` holds the reversal with its actor |
| A14 | pgTAP: a captured transaction with no line in a period the import reconciles; assert it is flagged, still present, and untouched |
| A15 | pgTAP: a descriptor never seen before; assert a merchant or alias is created, then apply a second fixture carrying the same descriptor and assert it resolves through the alias — and that no model call was made on either, which is inherent to the structured path |
| A16 | pgTAP impersonating `hh_member`: `insert` on `statement_import` and a call to `apply_statement_import` both fail at the database |
| A17 | `scripts/test-statement-parsers.sh`: every committed fixture parsed and compared to its `expected.json`, and each reconciled to its own stated closing balance or total |
| A18 | `scripts/test-statement-import.sh`: after applying, `v_period_reconciliation` reports the period reconciled; the digest rendered for the same period says so, and a period with no import does not |
| A19 | pgTAP: a flagged line, the clock advanced past every configured window; assert it is still flagged; then a bulk dismissal, asserted present in `audit_log` with its actor |
| A20 | `scripts/test-statement-import.sh`: render the monthly digest; assert the import reminder is a line in it and that no separate message was sent |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A parser is correct against its fixture and wrong against next month's real file — bank dialects in free-text fields, a changed column, a locale-dependent decimal | **high** | Parse only the structured fields and keep the descriptor raw (the spec's own edge case); the closing-balance check catches a wrong amount by refusing the import rather than applying it; a file that fails is kept, and a new fixture is the fix |
| The ICS CSV changes shape, and it is the one format with no closing balance | medium | Validation kind is recorded per import, so a silent drift to `override` is visible; A7a asserts the routine path never needs one |
| XLS is a moving target across providers and versions | medium | Converted to CSV at the parser's edge and then indistinguishable from the CSV path; a conversion that fails is a refusal, not a guess |
| Match tolerance creates false positives — two identical amounts at one merchant | medium | Reference first, tolerance second, ambiguity flagged rather than guessed (the spec's own rule); tolerance is per-account and tunable without a deploy |
| `apply_statement_import` grows into an untestable monolith | medium | Composed of named SQL functions with their own pgTAP tests — validate, match, create, supersede, flag — with the outer function only sequencing them in one transaction |
| An anonymised fixture still carries something real | low, high cost | `anonymise-statement.sh` replaces IBANs, card numbers, names and amounts; a committed guard test asserts no fixture contains an IBAN outside the documented invented range or a digit run long enough to be an account number; and the last check is a human one, recorded, because no script can tell an anonymised balance from a real one |
| A large import holds one long transaction | low | A month is hundreds of lines; if it ever stops being small, the fix is batching per period, not abandoning atomicity |

## ADRs required

- **ADR 0042 — statement parsing is a stateless service; reconciliation is a
  database function.** The split decides where financial truth is applied in
  bulk, it constrains every later import path (spec 0009 matches commitments
  through the same machinery, per ADR 0012), and it is the same class of
  decision ADR 0041 made for the token bridge. Drafted alongside this plan.
