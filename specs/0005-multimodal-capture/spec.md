---
id: 0005
title: Multimodal capture — receipt photos and voice notes
status: approved
created: 2026-09-12
updated: 2026-09-13
owner: admins
supersedes: []
---

# 0005 - Multimodal capture: receipt photos and voice notes

## Problem

Typing an amount is still typing, and at a till with a bag in one hand the
fastest honest record is a photograph of the receipt, while on the walk home it
is a sentence said out loud. People already do both with their phones, and the
system accepts neither.

This costs us most with the members who didn't build the system. Text capture is
enough for someone who is already motivated, but a photo is what keeps the habit
alive for everyone else, and the vision measures success by all three members
using it.

A receipt also carries more than a person would type: the merchant exactly as it
calls itself, the date, the total, and sometimes the category in the line items.

## Why

After this slice, a photo of a receipt or a voice note produces the same balanced
transaction that typing would, so the household's fastest way to capture an
expense needs no words at all.

We measure it two ways: photo and voice captures arrive from more than one
member, and the extraction is right often enough that correcting it is rare
rather than routine.

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
- **R4.** A multimodal model must handle voice directly, with no separate
  speech-to-text service (ADR 0029).
- **R5.** A photo must yield at least the total, the date, and the merchant, and
  where the receipt shows them, the currency and the line-item detail can inform
  the category.
- **R6.** When a receipt's date differs from the day it was sent, the system must
  use the receipt's date.
- **R7.** Every uploaded photo and voice note must be stored, content-addressed,
  and linked to the transaction it produced (ADR 0019).
- **R8.** The system must use a caption sent with a photo as a correction or a
  hint rather than ignoring it, so that "this was for the office" reaches the
  category decision.
- **R9.** Records from photo or voice must start unconfirmed, and the quiet-period
  rule must never auto-confirm them, however familiar the merchant (ADR 0023).
- **R10.** The confirmation reply must state what the model read from the image or
  audio, so the member catches a misreading at once.
- **R11.** A file the system cannot interpret must become an unparsed capture with
  the file retained and a question asked, under the same rule spec 0003's R17
  sets for text: a further question if an answer still leaves a gap, and never
  the same question twice.
- **R12.** Several photos sent together must each be treated as a separate
  capture, or as one capture if they are pages of a single receipt, and the
  system must ask rather than assume.
- **R13.** Extraction must use prompts held in this repository with declared
  output schemas, separate from the text-capture prompt (ADR 0025).
- **R14.** A voice note in Russian and a voice note in English must both work, and
  the reply must be in the member's language.
- **R15.** The system must record the cost of a capture per attempt (ADR 0029),
  because this is the slice where model spend becomes material.
- **R16.** When the model returns a receipt's line items, the system must store
  them alongside the transaction, unused for now.
- **R17.** The system must store a voice note's transcript in the audit record.
- **R18.** The first task of this slice must check that audio input reaches the
  chosen model through the gateway, and must record which of ADR 0029's fallbacks
  is needed if it doesn't.
- **R19.** Each task must carry a configured cost ceiling, above which the system
  refuses the call and asks the member to type the amount instead.
- **R20.** A member must be able to ask to **see the receipt** for a transaction
  and be sent the stored file, which is the reason the system keeps it at all.

## Scope

In scope: photo capture, voice capture, their prompts and schemas, file storage
and linking, the confirmation reply that echoes what the model read, captions as
hints, multi-page handling, and the golden-set entries for both.

Out of scope, with the reason for each:

- Statement PDFs, which spec 0007 covers. A statement isn't a receipt: it holds
  many transactions and it reconciles against ones already recorded.
- Splitting one receipt across categories, deferred for the same reason as in
  spec 0003: single-category capture has to be reliable first.
- Reading loyalty points, VAT breakdowns, or line items as separate records.
- Video, documents, and forwarded images from other chats.

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
      it states what was read - amount, merchant, date, category - in one short
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
      scores are recorded - and a prompt change that regresses extracted amounts
      or accounts is blocked (ADR 0025).
- [ ] **A14.** Given a capture whose projected cost exceeds the task's configured
      ceiling, when it is processed, then no model is called and the member is
      asked to type the amount.
- [ ] **A15.** Given a transaction created from a photo, when a member asks to see
      its receipt, then the stored image is sent back.

## Edge cases and failures

The states below are named from
[docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A blurred or partial receipt | Whatever is legible is extracted; anything missing is asked about, never invented |
| A receipt in Dutch | Normal case, not an edge case: statements and receipts here are Dutch |
| A receipt whose total and line items disagree | The printed total wins, and the member doesn't hear about the difference |
| A foreign-currency receipt | Recorded at the amount charged if the receipt shows it; otherwise unparsed, with a question |
| A photo that is not a receipt at all | Unparsed capture, one question, file retained |
| A very long voice note | Processed once; if it names several expenses, the system asks rather than recording part of them |
| A voice note with background noise and no clear amount | Unparsed capture |
| A photo of a screen showing a bank payment | Treated as a receipt, with the merchant it names |
| A file larger than the model accepts | Downscaled before sending, and the original is what the system stores |

## Ergonomic cost

- **Who does more work:** nobody, because this slice removes work. The one new
  cost lands on an admin: photo and voice records never auto-confirm, so the
  review queue grows with how much the household uses them, until spec 0007's
  reconciliation drains it.
- **What queue or obligation it creates:** unconfirmed records, deliberately
  exempt from auto-confirmation, drained by review and, from spec 0007, by
  matching, and bounded by the same ceiling alert.
- **What it interrupts, and how often:** one confirmation per capture, sent to
  the person who captured it. Nothing new.
- **If nobody touches it for a month:** nothing breaks. A larger share of that
  month's figures is unconfirmed, and every place the figures appear says so.

## Non-functional requirements

The figures below refine the shared baselines in
[docs/standards/budgets.md](../../docs/standards/budgets.md): a figure here is
stricter and says so, and where this section is silent the baseline applies.

- **Latency:** a confirmation within a few seconds for voice and within roughly
  ten seconds for a photo. Past that the member has put the phone away, so the
  reply has to arrive anyway and stand on its own.
- **Cost:** one model attempt per capture, with the model chosen per use case and
  the spend capped at the gateway (ADR 0029).
- **Privacy:** receipts are photographs of daily life, so the system stores them
  on the household's own volume (ADR 0019) and sends the gateway only the image
  the task needs, never the ledger.

## Open questions

None. We have decided everything this slice needed decided, and spec 0001 and
spec 0002 list what the household still has to supply.

## Related

- ADRs: 0029, 0008, 0013, 0019, 0023, 0025, 0027
- Specs: 0003 (must be done first), 0007 (drains the queue this fills)
