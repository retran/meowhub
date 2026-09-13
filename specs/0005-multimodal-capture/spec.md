---
id: 0005
title: Multimodal capture — receipt photos and voice notes
status: review
created: 2026-09-12
updated: 2026-09-12
owner: admins
supersedes: []
---

# 0005 — Multimodal capture: receipt photos and voice notes

## Problem

Typing an amount is still typing. At a till with a bag in one hand, the fastest
honest record is a photograph of the receipt; walking home, it is a sentence said
out loud. Both are things people already do with their phones, and neither is
currently accepted.

This matters most for the members who did not build the system. Text capture is
enough for someone motivated; a photo is what makes the habit survive for
everyone else — and the vision's measure of success is that all three members
use it.

A receipt also carries more than a person would type: the merchant exactly as it
calls itself, the date, the total, sometimes the category in the line items.

## Why

After this slice, a photo of a receipt or a voice note produces the same balanced
transaction that typing would, and the household's fastest capture becomes the
one that requires no words at all.

The measure: photo and voice captures appear from more than one member, and their
extraction is right often enough that correcting them is rare rather than routine.

## Users and scenarios

- **A member** wants to photograph a receipt and be done, with no typing.
- **A member** wants to say "coffee three fifty" while walking and have it land.
- **A member** wants to photograph a payment confirmation screen, not only paper.
- **An admin** wants the same confirmation state and review path as text capture,
  because a photo is still a guess.

## Requirements

- **R1.** A member must be able to send a photo and have an expense recorded from
  it, with no accompanying text.
- **R2.** A member must be able to send a voice note and have an expense recorded
  from it, with no accompanying text.
- **R3.** Both must produce the same kind of balanced transaction as text capture,
  with the same defaults for the payment account (spec 0003).
- **R4.** Voice must be handled by a multimodal model directly, with no separate
  speech-to-text service (ADR 0029).
- **R5.** A photo must yield at least the total, the date and the merchant; where
  the receipt shows them, the currency and the line-item detail may inform the
  category.
- **R6.** Where a receipt's date differs from the day it was sent, the receipt's
  date must win.
- **R7.** Every uploaded photo and voice note must be stored, content-addressed,
  and linked to the transaction it produced (ADR 0019).
- **R8.** A caption sent with a photo must be used as a correction or a hint, not
  ignored — "this was for the office" must reach the category decision.
- **R9.** Records from photo or voice must start unconfirmed, and must never be
  auto-confirmed on the quiet-period rule, however familiar the merchant
  (ADR 0023).
- **R10.** The confirmation reply must state what was read from the image or audio,
  so a misreading is caught at once.
- **R11.** A file that cannot be interpreted must become an unparsed capture with
  the file retained and one question asked (spec 0003, R17).
- **R12.** Several photos sent together must each be treated as a separate
  capture, or, if they are pages of one receipt, as one — and the system must ask
  rather than assume.
- **R13.** Extraction must use prompts held in this repository with declared output
  schemas, separate from the text-capture prompt (ADR 0025).
- **R14.** A voice note in Russian or English must both work, and the reply must be
  in the member's language.
- **R15.** The cost of a capture must be recorded per attempt (ADR 0029), because
  this is the slice where model spend becomes material.
- **R16.** Where a receipt's line items are returned, they must be stored
  alongside the transaction, unused for now.
- **R17.** A voice note's transcript must be stored in the audit record.
- **R18.** The first task of this slice must be to verify that audio input reaches
  the chosen model through the gateway, and to record which of ADR 0029's
  fallbacks is needed if it does not.
- **R19.** Each task must carry a configured cost ceiling; above it the call is
  refused and the member is asked to type the amount instead.
- **R20.** A member must be able to ask to **see the receipt** for a transaction
  and be sent the stored file — the reason it is kept at all.

## Scope

**In scope:** photo capture, voice capture, their prompts and schemas, file
storage and linking, the confirmation reply that echoes what was read, captions
as hints, multi-page handling, and the golden-set entries for both.

**Out of scope (and why):**
- Statement PDFs (spec 0007). A statement is not a receipt: it is many
  transactions and it reconciles against existing ones.
- Splitting one receipt across categories. Deferred with the same reasoning as
  spec 0003: single-category capture must be reliable first.
- Reading loyalty points, VAT breakdowns or line items as separate records.
- Video, documents and forwarded images from other chats.

## Acceptance criteria

- [ ] **A1.** Given a photograph of a supermarket receipt, when it is sent with no
      text, then a transaction is recorded with the receipt's total, its date and
      its merchant, and it is unconfirmed.
- [ ] **A2.** Given a receipt dated three days ago, when it is captured today, then
      the transaction is dated three days ago.
- [ ] **A3.** Given a voice note saying an amount and a merchant, when it is sent,
      then a transaction is recorded matching it.
- [ ] **A4.** Given a voice note in Russian, when it is sent by a member whose
      language is Russian, then the transaction is recorded and the reply is in
      Russian.
- [ ] **A5.** Given any photo or voice capture, when the confirmation is sent, then
      it states what was read — amount, merchant, date, category — in one short
      message.
- [ ] **A6.** Given a photo with a caption naming a category, when it is captured,
      then the caption's category is used over the model's own guess.
- [ ] **A7.** Given a photo or voice capture at a merchant already known and below
      the auto-confirm threshold, when the quiet period passes, then it is still
      unconfirmed.
- [ ] **A8.** Given an unreadable photo, when it is sent, then no transaction
      exists, the file is stored, and one question is asked.
- [ ] **A9.** Given the same photo sent twice, when both are processed, then one
      file is stored and the duplicate is recognised.
- [ ] **A10.** Given two photos of the pages of one receipt, when they are sent
      together, then the system asks whether they are one expense rather than
      recording two.
- [ ] **A11.** Given any capture, when it is inspected in the database, then the
      stored file is linked to the transaction and the model, prompt version and
      cost are recorded.
- [ ] **A12.** Given the model gateway is unavailable, when a photo is sent, then
      the file is stored, the capture is unparsed, and nothing is lost.
- [ ] **A13.** Given the golden set for photo and voice, when it is run, then the
      scores are recorded — and a prompt change that regresses extracted amounts
      or accounts is blocked (ADR 0025).
- [ ] **A14.** Given a capture whose projected cost exceeds the task's configured
      ceiling, when it is processed, then no model is called and the member is
      asked to type the amount.
- [ ] **A15.** Given a transaction created from a photo, when a member asks to see
      its receipt, then the stored image is sent back.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A blurred or partial receipt | Whatever is legible is extracted; anything missing is asked about, never invented |
| A receipt in Dutch | Normal case, not an edge case: statements and receipts here are Dutch |
| A receipt whose total and line items disagree | The printed total wins; the discrepancy is not reported to the member |
| A foreign-currency receipt | Recorded at the amount charged if it is on the receipt; otherwise unparsed with a question |
| A photo that is not a receipt at all | Unparsed capture, one question, file retained |
| A very long voice note | Processed once; if it contains several expenses, the system asks rather than recording part |
| A voice note with background noise and no clear amount | Unparsed capture |
| A photo of a screen showing a bank payment | Treated as a receipt; the merchant is whatever it names |
| A file larger than the model accepts | Downscaled before sending; the original is what is stored |

## Ergonomic cost

- **Who does more work:** nobody — this removes work. The one new cost lands on
  an admin: photo and voice records never auto-confirm, so the review queue grows
  in proportion to their use, until spec 0007's reconciliation drains it.
- **What queue or obligation it creates:** unconfirmed records, deliberately
  exempt from auto-confirmation. Drained by review and, from spec 0007, by
  matching. Bounded by the same ceiling alert.
- **What it interrupts, and how often:** one confirmation per capture, to the
  person who captured. Nothing new.
- **If nobody touches it for a month:** nothing breaks; the unconfirmed share of
  that month's figures is higher, and stated wherever the figures appear.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **Latency:** a confirmation within a few seconds for voice, and within roughly
  ten for a photo. Beyond that the member has put the phone away, so the reply
  must arrive anyway and stand on its own.
- **Cost:** one model attempt per capture, with the model chosen per use case and
  the spend capped at the gateway (ADR 0029).
- **Privacy:** receipts are photographs of daily life. They are stored on the
  household's own volume (ADR 0019), and only the image needed for the task is
  sent to the gateway — never the ledger.

## Open questions

None. Everything this slice needed decided has been decided; what the household
must still supply is listed in spec 0001 and spec 0002.

## Related

- ADRs: 0029, 0008, 0013, 0019, 0023, 0025, 0027
- Specs: 0003 (must be done first), 0007 (drains the queue this fills)
