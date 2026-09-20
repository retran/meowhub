---
id: 0013
title: Statement ingestion — structured formats first, PDF through the model as a fallback
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0013 - Statement ingestion: structured formats first, PDF through the model as a fallback

## Context

The books are only trustworthy if they agree with the bank (vision principle 9),
so importing statements is what turns the ledger from what the household
remembered into what actually happened.

A statement is most obviously offered as a PDF, and we decided not to build on
that format, because every provider the household uses also offers something a
parser can read:

- ABN AMRO and ING both export CAMT.053 (ISO 20022 XML), MT940, XLS, TXT and
  PDF. Dutch accounting guidance says the PDF *rekeningafschrift* is for reading
  and that you import MT940 or CAMT.053.
- SWIFT withdrew support for MT940 in November 2025 and names CAMT.053 as its
  successor, because CAMT.053 carries richer per-transaction detail and shows
  what is inside a batched transaction, which MT940 loses.
- ICS exports transactions as CSV only. It offers no MT940, and its PDF is a
  copy of the statement.

We still can't drop PDF, because a PDF is what exists for an old period, for a
provider that changes its export, for a one-off document, and for anything that
arrives as a forwarded attachment rather than a deliberate download. The owner
asked for both ways in.

The two paths differ in something that matters more than the file format. A
parser reads a structured export the same way every time, while the model path
is a model's reading of a picture, so treating the two as interchangeable would
let a hallucinated amount into the household's financial truth.

## Decision

We support both paths, turn both into the same statement lines, and keep a
record on every line of how much we trust it.

### One normalised target

Every import, whatever the format, produces **statement lines** in one shape
that owes nothing to the source format: account, booking date, value date,
amount in minor units, currency, the provider's own transaction reference where
it has one, the raw descriptor, and whatever counterparty details the format
carried.

Each line records its provenance: the source file, its format, which parser or
model produced it, and, on the model path, what the model returned.
Reconciliation then runs over statement lines and knows nothing about where they
came from, so it is the same code that matches commitments and planned purchases
(ADR 0012).

### Structured is authoritative, PDF is provisional

- CAMT.053 is the format we prefer for the banks, we accept MT940 for historical
  files, CSV is the path for ICS and for any provider that offers nothing
  better, and we treat XLS as CSV.
- A structured parse is **authoritative**, because no model is involved: there
  is nothing to second-guess and no per-import cost.
- A PDF-derived line is provisional. We mark it as model-derived, and when a
  structured export covering the same account and period arrives later, that
  export supersedes the line instead of duplicating it. Re-importing is
  therefore how PDF data gets upgraded, not how double entries appear.

### The statement's own totals are the checksum

Both CAMT.053 and a readable PDF carry opening and closing balances, so we
accept an import only when its lines reconcile to the closing balance for the
period. If they don't, we apply nothing and reject the import with the
discrepancy shown. That check is what makes the model path safe enough to
allow: a misread amount produces a refused import rather than a plausible wrong
ledger.

### Imports are batches, and reversible

- An import is one recorded batch, with its file, its provenance and its
  outcome.
- Re-importing the same file changes nothing, because we key idempotency on the
  provider's transaction reference where the format supplies one, and on a
  content fingerprint plus matching where it does not.
- You can undo an import as a unit. Reconciling one file can create and modify
  many transactions at once, so reversing the whole batch is a requirement
  rather than a convenience, and ADR 0008's audit log is what makes the reversal
  verifiable.

### Cost and privacy follow the split

We call the model only on the PDF path, so the recurring case costs nothing and
sends nothing outside the household. A PDF sent to the model is a whole
statement, which is more sensitive than a single capture, and that is the second
reason the PDF path is the fallback.

## Alternatives

| Option | Why rejected |
|---|---|
| PDF plus a vision model as the only path | Puts a model in the path of the household's financial truth, paid per page, with errors that look plausible - when a deterministic export exists for every provider the household uses |
| Structured formats only, no PDF at all | Cleaner and cheaper, but the owner rejected it because it leaves historical periods, one-off documents and forwarded attachments with no way in |
| Treat both paths identically once parsed | Loses the difference between a parsed number and a guessed one, which is the difference that makes allowing PDFs acceptable |
| MT940 as the primary format | Widely documented and simple, but SWIFT is retiring it, and it hides what is inside a batched transaction |
| Bank APIs or PSD2 aggregators | The vision puts them out of scope, and they would place a third party inside the books |
| A third-party converter (CSV to MT940 and similar) | Adds a dependency and a format hop to reach a format we don't want anyway |

## Consequences

**Good:**
- The common case, a monthly download from each provider, is deterministic,
  free and exact.
- PDFs still work, so no period and no document is out of reach.
- A misread PDF can't quietly corrupt the books, because the closing-balance
  check refuses the import.
- Commitments, planned purchases and statements all go through the same
  reconciliation code, so they can't drift apart.
- Re-importing is safe, and for PDF-derived data it replaces guesses with parsed
  numbers.

**Bad, and the price we accept:**
- We have four input formats to parse, plus the model path, which is more code
  than a single format would need. CAMT.053 in particular is verbose XML, and
  banks differ in how they fill its free-text fields.
- The app and the reports have to show which lines are provisional and which are
  authoritative, or the household will forget the difference exactly when it
  matters.
- The closing-balance check will sometimes refuse an import that a person can
  see is fine, such as a mid-period export or an unusual batched transaction. We
  need a documented override, and it has to be recorded as an override.
- Statement files, PDFs included, are the most sensitive data the system holds,
  and they now pile up in the database and in the backups.

**What becomes harder to change later:**
- The normalised statement-line shape, once imports have run against it. That is
  why we keep it format-agnostic and carrying provenance from the first
  migration, instead of modelling it on whichever format we implement first.
