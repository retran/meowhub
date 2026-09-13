---
id: 0013
title: Statement ingestion — structured formats first, PDF through the model as a fallback
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0013 — Statement ingestion: structured formats first, PDF through the model as a fallback

## Context

The books are only trustworthy if they agree with the bank (vision principle 9),
so importing statements is what turns the ledger from "what we remembered" into
"what actually happened".

PDF is the format a statement is most obviously *offered* in, and the wrong one to
build on. What the household's providers actually offer:

- **ABN AMRO and ING** both export **CAMT.053** (ISO 20022 XML), MT940, XLS, TXT
  and PDF. Dutch accounting guidance is explicit that the PDF *rekeningafschrift*
  is for reading and that MT940 or CAMT.053 is what you import.
- **MT940 is being retired** — SWIFT withdrew support in November 2025, with
  CAMT.053 as the successor, carrying richer per-transaction detail and visibility
  into batched transactions that MT940 loses.
- **ICS** exports transactions as **CSV only**. MT940 is not offered; its PDF is a
  statement copy.

So a structured path exists for every provider the household uses. But PDF cannot
simply be dropped: it is what exists for an old period, for a provider that
changes its export, for a one-off document, and for anything arriving as a
forwarded attachment rather than a deliberate download. The owner wants both.

The two paths differ in a way that matters more than file format: one is
deterministic and the other is a model's reading of a picture. Treating them as
interchangeable would put a hallucinated amount into the household's financial
truth.

## Decision

**Support both, normalise both, and never confuse their trustworthiness.**

### One normalised target

Every import — whatever the format — produces **statement lines** in one
format-agnostic shape: account, booking date, value date, amount in minor units,
currency, the provider's own transaction reference where it has one, the raw
descriptor, and the counterparty details the format happened to carry.

Each line records its **provenance**: the source file, its format, which parser or
model produced it, and for the model path, what the model returned. One
reconciliation mechanism then runs over statement lines and knows nothing about
where they came from — the same mechanism that matches commitments and planned
purchases (ADR 0012).

### Structured is authoritative, PDF is provisional

- **CAMT.053** is the preferred format for the banks; **MT940** is accepted for
  historical files; **CSV** is the path for ICS and for any provider that offers
  nothing better; **XLS** is treated as CSV.
- **A structured parse is authoritative.** No model is involved, so there is
  nothing to second-guess and no per-import cost.
- **A PDF-derived line is provisional.** It is marked as model-derived and is
  **superseded, not duplicated**, when a structured export covering the same
  account and period arrives later. Re-import is therefore an upgrade path rather
  than a source of double entries.

### The statement's own totals are the checksum

Both CAMT.053 and a readable PDF carry opening and closing balances. An import is
accepted only if the lines reconcile to the closing balance for the period.
**If they do not, nothing is applied** — the import is rejected with the
discrepancy shown. This is what makes the model path safe enough to allow: a
misread amount does not produce a plausible wrong ledger, it produces a refused
import.

### Imports are batches, and reversible

- An import is one recorded batch with its file, its provenance and its outcome.
- **Re-importing the same file changes nothing.** Idempotency keys on the
  provider's transaction reference where the format supplies one, and on a
  content fingerprint plus matching where it does not.
- **An import can be undone as a unit.** A reconciliation can create and modify
  many transactions at once, so the ability to reverse one wholesale is a
  requirement, not a convenience — and it is what ADR 0008's audit log makes
  verifiable.

### Cost and privacy follow the split

The model is invoked only on the PDF path, so the recurring case costs nothing and
sends nothing outside the household. A PDF sent to the model is a whole statement
— more sensitive than a single capture — which is another reason it is the
fallback and not the default.

## Alternatives

| Option | Why rejected |
|---|---|
| PDF plus a vision model as the only path | Puts a model in the path of the household's financial truth, paid per page, with errors that look plausible — when a deterministic export exists for every provider the household uses |
| Structured formats only, no PDF at all | Cleaner, cheaper, and rejected by the owner for good reason: it leaves historical periods, one-off documents and forwarded attachments with no way in |
| Treat both paths identically once parsed | Loses the distinction between a parsed number and a guessed one, which is precisely the distinction that makes allowing PDFs acceptable |
| MT940 as the primary format | Widely documented and simple, but being retired, and it hides the detail of batched transactions |
| Bank APIs or PSD2 aggregators | Explicitly out of scope in the vision, and would place a third party inside the books |
| A third-party converter (CSV to MT940 and similar) | Adds a dependency and a format hop to reach a format we do not want anyway |

## Consequences

**Good:**
- The common case — a monthly download from each provider — is deterministic,
  free and exact.
- PDFs remain possible, so no period or document is unreachable.
- A misread PDF cannot quietly corrupt the books: the closing-balance check
  refuses the import instead.
- One reconciliation mechanism, shared with commitments and planned purchases.
- Re-importing is safe and, for PDF-derived data, an improvement.

**Bad, and the price we accept:**
- Four input formats to support, plus the model path — more parsing surface than
  a single format would need. CAMT.053 in particular is verbose XML, and banks
  differ in how they fill its free-text fields.
- The provisional-versus-authoritative distinction must be visible in the app and
  in reports, or it will be forgotten precisely when it matters.
- The closing-balance invariant will sometimes refuse an import that a human can
  see is fine — a mid-period export, an unusual batched transaction. A documented
  override is needed, and it must be recorded as an override.
- Statement files, including PDFs, are the most sensitive data the system holds,
  and they now accumulate in the database and the backups.

**What becomes harder to change later:**
- The normalised statement-line shape, once imports have run against it. Hence
  keeping it format-agnostic and provenance-carrying from the first migration,
  rather than modelled on whichever format is implemented first.
