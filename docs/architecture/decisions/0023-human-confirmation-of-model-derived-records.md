---
id: 0023
title: Model-derived records are unconfirmed until a human or the bank confirms them
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0023 — Model-derived records are unconfirmed until a human or the bank confirms them

## Context

A model turns "coffee 350" into a balanced transaction by inferring things nobody
said: which merchant, which category, which account. It will sometimes infer
wrongly, and the design already accepts that (vision principle 8). What it does
not yet provide is a way for a human to say **"I have looked at this and it is
right"** — so today a guessed entry and a verified one are indistinguishable in
the books.

The owner wants the obvious remedy: the agent records, and he reviews and approves
in the app.

This also resolves a tension in ADR 0016. Editing recorded transactions is
admin-only, which left a member who is not an admin's typo requiring a notification, a reply and a
correction — three messages and a wait. A review pass is where that correction
naturally belongs.

The danger is equally clear, and it is the reason this needs a decision rather
than a feature: **an approval queue that grows faster than anyone drains it is
worse than no approval at all.** It becomes a permanent guilty backlog, everything
in it is eventually rubber-stamped unread, and the state then means nothing.

## Decision

Every transaction carries a **confirmation state**: `unconfirmed` or `confirmed`,
with who confirmed it, when, and by which route.

### What needs confirming, and what does not

- **Model-derived records start unconfirmed**: text captures, photo and voice
  captures, and PDF-derived statement lines (ADR 0013).
- **Deterministic records are born confirmed**: opening balances, structured
  statement imports (CAMT.053, CSV), and anything an admin enters or edits by
  hand. There is nothing for a human to second-guess in a parsed XML amount.

Confirmation is **orthogonal to provenance**: provenance says how good the source
was, confirmation says whether a human has vouched for it. A provisional PDF line
that has been reviewed is confirmed-but-provisional, and both facts stay visible.

### Three routes to confirmed, and two of them are not work

1. **Review in the app.** A queue of unconfirmed transactions, newest first,
   designed for a thumb: each row shows the amount, merchant, category and
   account with the inferred fields marked, and the actions are approve, fix, or
   delete. **Batch approval is the primary action** — select many, approve once.
   Fixing is inline; it is the same edit an admin-only correction would be, so the
   review pass is also the correction pass.
2. **The bank confirms it.** A transaction matched to an *authoritative* statement
   line during reconciliation becomes confirmed automatically. This is the
   strongest confirmation available — stronger than a human glance — and it means
   the monthly import drains most of the queue by itself.
3. **Silence, but only where it is safe.** A capture is auto-confirmed after a
   quiet period when **all** of these hold: the merchant was already known, the
   category came from the merchant's default rather than from the model, the
   amount is below a configured threshold, and nobody has touched it. Everything
   else waits for route 1 or 2.

Route 3 is what keeps the queue finite, and its conditions are deliberately
conservative: it auto-confirms the boring repetitions, never a guess.

### Rules that keep the state honest

- **Unconfirmed transactions count in the books.** Balances and reports include
  them, because a ledger that lags reality is useless. Reports show the
  **unconfirmed share** for the period, so a number can be trusted in proportion.
- **Confirming changes nothing financial.** It is a statement about review, not an
  edit; it never moves an amount or an account.
- **Any member may confirm their own capture.** That is not editing a financial
  fact, and it is the narrow, safe answer to ADR 0016's collision with "a wrong
  entry must be cheap to fix": you may vouch for what you entered, and correcting
  it is still the owner's.
- **Editing an unconfirmed record does not require the approval round trip.**
  Whether that window should *also* be time-bounded — minutes, rather than "until
  someone vouches for it" — is an open question on spec 0003.
- **The queue has a ceiling, and the ceiling is an alert.** If unconfirmed items
  older than a configured age exceed a threshold, the admins are told once — because
  a queue nobody drains is a process failure, not a data state.
- **Confirmation is audited** like every other change (ADR 0008): who vouched,
  when, and by which route.

## Alternatives

| Option | Why rejected |
|---|---|
| No confirmation state, as before | A guessed entry and a verified one look identical, so the only way to trust a total is to re-read every row |
| Hold unconfirmed records out of the books until approved | Balances would then disagree with reality until someone did paperwork, and a household's whole reason to capture instantly is to *have* the number now |
| Confirm one transaction at a time, modally | The interaction that guarantees the queue is never drained. Batch approval is the feature, not a refinement of it |
| Auto-confirm everything after a timeout | Makes the state a formality: everything becomes confirmed whether or not anyone looked, so it stops meaning anything |
| Never auto-confirm anything | The purist position, and it produces the unbounded backlog this ADR exists to prevent. Boring repetitions at a known merchant are exactly what a human adds nothing to |
| Use model confidence as the state | A model's confidence is not a human's judgement and is not well calibrated. It may *inform* route 3's conditions; it may not stand in for them |
| Reuse the provisional/authoritative distinction | Conflates source quality with review. A deterministic CSV line is authoritative and may still be worth a glance; a reviewed PDF line is checked and still provisional |

## Consequences

**Good:**
- A total can be trusted in proportion: the unconfirmed share is visible rather
  than hidden.
- The review pass is the correction pass, which removes ADR 0016's
  notification ping-pong and gives non-owner members a way to fix things — by
  having them fixed in one place, quickly.
- Reconciliation drains most of the queue automatically, so the manual load falls
  as the books get more complete rather than rising with volume.
- Auto-confirmation makes the merchant registry pay off twice: known merchants
  cost neither a model call nor a review.

**Bad, and the price we accept:**
- **A new recurring chore exists.** It is bounded by three mechanisms, and it is
  still a chore, and the admins are still the people who do most of it.
- Two orthogonal quality dimensions — provenance and confirmation — must be shown
  without confusing anyone. The design system has to carry that (ADR 0022), and
  it is the likeliest place for the interface to get muddy.
- Auto-confirmation thresholds are judgement calls that will be wrong at first,
  and tuning them is tuning trust.
- Every report now needs the unconfirmed share alongside its figure, which is one
  more thing on a small screen.

**What becomes harder to change later:** the meaning of `confirmed` in historical
data. If the auto-confirmation rules change, old rows were confirmed under
different ones — so the route is recorded per row, and reports can distinguish
"a person looked" from "the bank agreed" from "it was quiet".
