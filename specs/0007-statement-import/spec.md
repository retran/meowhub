---
id: 0007
title: Statement import and reconciliation
status: review
created: 2026-09-12
updated: 2026-09-12
owner: admins
supersedes: []
---

# 0007 — Statement import and reconciliation

## Problem

Up to this point the books record what the household *remembered*. Captures are
missed, amounts are mistyped, and a fortnight of holiday leaves a hole. A ledger
that only contains what someone thought to mention cannot be reconciled with
anything, so nobody can tell whether it is complete — and a figure nobody can
check is a figure nobody acts on.

The banks and the card issuer already publish the truth. ABN AMRO and ING export
CAMT.053, MT940, XLS and PDF; ICS exports CSV and a PDF statement copy. Importing
those closes the loop: what actually left the accounts, matched against what was
captured by hand.

This is also the slice that makes two earlier decisions pay off. A matched record
is confirmed by the bank — stronger than a human glance — so reconciliation drains
the confirmation queue automatically (ADR 0023). And the card settlement that
would otherwise double-count becomes a transfer, exactly as the double-entry model
promised (ADR 0011).

## Why

After this slice, an admin uploads three files a month and the books become
complete: missing expenses appear, duplicates are recognised rather than added,
the card bill is a transfer rather than a second purchase, and account balances
agree with the statements.

The measure: for a closed month, each account's balance in the books equals the
statement's closing balance, and any difference is explainable rather than
mysterious.

## Users and scenarios

- **An admin** wants to upload a bank export and have the month completed, without
  reviewing every line.
- **An admin** wants to see what an import *would* do before it does it.
- **An admin** wants a mistaken import undone in one action.
- **An admin** wants the card bill not to be counted as spending.
- **A member** wants the expenses they captured to be recognised as the same ones
  on the statement, not duplicated beside them.

## Requirements

### Reading

- **R1.** An admin must be able to upload a statement in the chat or the app and
  have it imported.
- **R2.** CAMT.053 must be supported, and is the preferred format for the banks.
- **R3.** MT940 must be supported, for files from before its retirement.
- **R4.** CSV must be supported, including the ICS card export, and XLS treated as
  CSV.
- **R5.** PDF must be supported through a multimodal model, producing provisional
  lines (ADRs 0013, 0029).
- **R6.** Every format must normalise to one statement-line shape: account,
  booking date, value date, amount in minor units, currency, the provider's own
  transaction reference where it exists, the raw descriptor, and counterparty
  details where the format carries them.
- **R7.** Every line must record its provenance: the file, its format, the parser
  or model, and for the model path the prompt version and response.
- **R8.** Every uploaded file must be stored content-addressed and linked to the
  import (ADR 0019).
- **R9.** An import must be rejected in full if its lines do not reconcile to the
  statement's closing balance; a partial application is never acceptable.
- **R9a.** Where a format carries **no closing balance** — the ICS card CSV being
  the case that matters — the import must be validated another way rather than by
  routinely overriding R9, which would turn the control into a formality. Two
  checks that do not need a balance: the file's own stated total, and agreement
  between the card's period total and the settlement amount that later appears on
  the bank statement. An import validated this way must record which check was
  used.
- **R10.** An admin must be able to override a rejected import deliberately, and
  the override must be recorded as one.
- **R11.** Re-importing the same file must change nothing.

### Matching

- **R12.** A statement line must be matched against existing transactions on the
  same account by amount and approximate date, using the provider's reference
  where available.
- **R13.** A matched transaction must become confirmed, with the route recorded as
  the bank (ADR 0023).
- **R14.** An unmatched line must create a transaction, attributed to the import
  rather than to a member, and marked confirmed — the bank is the source.
- **R15.** A line recognised as a payment to the credit card must be recorded as a
  transfer between accounts, never as spending (ADR 0011).
- **R15a.** Recognition of a settlement must use the counterparty IBAN first and
  the descriptor only as a fallback, with an admin-configurable rule per liability
  account.
- **R15b.** The match tolerance must default to five days and be configurable per
  account.
- **R16.** Interest, fees and other bank charges must post to their own expense
  accounts rather than to a category.
- **R17.** A captured transaction with no corresponding statement line in a
  reconciled period must be flagged for review, not deleted — it may be a capture
  error or a card purchase not yet settled.
- **R18.** A provisional, model-derived line must be superseded rather than
  duplicated when a structured export covering the same account and period is
  imported later.
- **R19.** Merchants must be recognised from statement descriptors through the
  alias registry, and a new descriptor must become an alias or a new merchant
  (ADR 0004).

### Operating

- **R20.** An import must be a recorded batch with its file, its provenance, its
  outcome and its counts.
- **R21.** An admin must be able to preview an import — what would be created,
  matched, superseded and flagged — before applying it.
- **R22.** An admin must be able to reverse an entire import in one action, and
  the reversal must itself be audited (ADR 0008).
- **R23.** Only an admin may import, override, or reverse (ADR 0016).
- **R24.** A reconciled period must be visible as reconciled wherever its figures
  appear.
- **R25.** The slice's first task must be to obtain one real export per provider,
  anonymise it, and commit it as a fixture; parsers are written against fixtures,
  never against a format's documentation alone.
- **R26.** A flagged line or capture must never resolve itself on a timer. It
  stays until reviewed, with a visible count and an audited bulk dismissal.
- **R27.** The monthly reminder to import must be a line in the monthly digest,
  not a message of its own.
- **R28.** Where a statement line carries an original amount and currency as well
  as the amount charged, both must be stored (spec 0003, R28).
- **R29.** Reviewing flagged lines must offer the closed choices as buttons —
  match to this transaction, create new, dismiss — with typed equivalents
  (ADR 0035).

## Scope

**In scope:** the parsers for CAMT.053, MT940, CSV and XLS; the PDF path and its
prompt and schema; the normalised statement-line model; the closing-balance
check; matching and its outcomes; card settlement as a transfer; interest and fee
posting; import batches, preview and reversal; the reconciliation review screen;
descriptor-to-merchant learning; anonymised fixtures for every format.

**Out of scope (and why):**
- Bank APIs and PSD2 aggregators — out by the vision.
- Loan amortisation schedules and cost-of-credit reporting (spec 0008). Interest
  lines post correctly here; their recurring structure comes next.
- Splitting a statement line across categories.
- Investment or savings accounts.
- Automatic download from the banks. The upload is manual, deliberately: it is
  three files a month and it needs no credentials stored anywhere.

## Acceptance criteria

- [ ] **A1.** Given a CAMT.053 export for a month, when imported, then every line
      becomes a statement line with its reference, and the account's balance after
      import equals the statement's closing balance.
- [ ] **A2.** Given the same file imported twice, when the second import runs, then
      nothing changes and the import records that it was a duplicate.
- [ ] **A3.** Given an ICS CSV export, when imported, then each card purchase posts
      against the card liability and none of them touch a bank account.
- [ ] **A4.** Given a bank export containing the monthly payment to ICS, when
      imported, then it is recorded as a transfer, the card liability falls, and
      the month's spending total does not change.
- [ ] **A5.** Given an expense captured by hand and the same expense on the
      statement, when imported, then one transaction exists, it is confirmed, and
      the route is recorded as the bank.
- [ ] **A6.** Given a statement line with no captured counterpart, when imported,
      then a confirmed transaction is created, attributed to the import.
- [ ] **A7.** Given a statement whose lines do not sum to its closing balance, when
      imported, then nothing is applied and the discrepancy is reported.
- [ ] **A7a.** Given an ICS CSV with no closing balance, when imported, then it is
      validated by an alternative check, the check used is recorded, and no
      override was required — an override on the routine monthly path is a defect.
- [ ] **A8.** Given the same statement with a deliberate override, when applied,
      then it imports and the override is recorded with its actor.
- [ ] **A9.** Given a PDF statement, when imported, then its lines are provisional
      and visibly so.
- [ ] **A10.** Given a period first imported from PDF and later from CAMT.053, when
      the second import runs, then the provisional lines are superseded, not
      duplicated, and the balances are those of the structured file.
- [ ] **A11.** Given an overdraft interest charge on a statement, when imported,
      then it posts to the interest expense account and not to a spending
      category.
- [ ] **A12.** Given an import, when previewed, then the counts of created, matched,
      superseded and flagged lines are shown and nothing is written.
- [ ] **A13.** Given an applied import, when it is reversed, then every transaction
      it created is gone, every confirmation it granted is withdrawn, balances
      return to their prior values, and the reversal is in the audit record.
- [ ] **A14.** Given a captured transaction with no statement line in a reconciled
      period, when the import completes, then it is flagged for review and not
      deleted.
- [ ] **A15.** Given a statement descriptor never seen before, when imported, then a
      merchant or alias is created, and the next statement matches it without a
      model call.
- [ ] **A16.** Given a member who is not an admin, when an import is attempted, then
      it fails at the database.
- [ ] **A17.** Given the anonymised fixtures for each supported format, when the
      parser tests run, then each produces the expected normalised lines and
      reconciles to its stated closing balance.
- [ ] **A18.** Given a period that has been reconciled, when its figures appear in
      the app and in a digest, then both show it as reconciled — and an
      unreconciled period is not shown as though it were.
- [ ] **A19.** Given a flagged line left unreviewed for any length of time, when
      the system runs, then it is still flagged — nothing resolves on a timer —
      and a bulk dismissal is recorded in the audit log with its actor.
- [ ] **A20.** Given the monthly digest, when it renders, then it contains the
      reminder to import, and no separate reminder message was sent.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A statement covering a period that overlaps an earlier import | Only the lines not already present are created; the overlap is reported |
| A mid-period export with no closing balance | Validated by R9a's alternative checks where possible; only a file with none of them requires an explicit, recorded override |
| A card purchase in a statement period before it is settled | Posts to the card liability on its own date; the later settlement is the transfer |
| A refund or reversal on the statement | A negative expense against the same account and category, not a deletion |
| A foreign-currency transaction with a conversion fee | Recorded at the EUR amount charged; the fee posts to fees |
| Two identical amounts at the same merchant on the same day | Matching is ambiguous: both are flagged rather than guessed |
| A statement line matching a transaction captured on a different account | Flagged, not silently re-attributed — the account is a financial fact |
| A CAMT.053 file with a bank-specific dialect in its free-text fields | Parsed for the structured fields; the descriptor is kept raw for alias matching |
| A PDF whose total is legible but whose lines are not | Rejected by the closing-balance check rather than partially imported |
| A file that is not a statement at all | Rejected with a plain message; the file is retained |
| An import interrupted halfway | Applied atomically or not at all |

## Ergonomic cost

- **Who does more work:** an admin, once a month: three downloads and three
  uploads. This is the household's largest recurring chore, and it is named in the
  chore table in `docs/standards/ergonomics.md`.
- **What queue or obligation it creates:** flagged lines — ambiguous matches and
  captures with no statement line. Bounded by the volume of one month, and drained
  in the reconciliation review. It **drains** the far larger confirmation queue.
- **What it interrupts, and how often:** one monthly reminder, and the import's own
  result. Nothing else.
- **If nobody touches it for a month:** the books stay incomplete and say so — the
  unreconciled periods are visible. Nothing is lost, and two months can be
  imported in one sitting.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **A structured import costs nothing**: no model call in the common path.
- **An import of a month completes in seconds**, and is atomic.
- **Statement files are the most sensitive data the system holds**: stored on the
  household's own volume, in the EU, and included in the encrypted backups
  (ADRs 0009, 0019, 0028).
- **No real statement is ever committed as a fixture**; fixtures are anonymised
  (ADR 0015).

## Open questions

None. Everything this slice needed decided has been decided; what the household
must still supply is listed in spec 0001 and spec 0002.

## Related

- ADRs: 0004, 0008, 0011, 0013, 0016, 0019, 0023, 0029
- Specs: 0003 and 0004 (must be done first), 0006 (carries the review screen), 0008
