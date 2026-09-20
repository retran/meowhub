---
id: 0023
title: Model-derived records are unconfirmed until a human or the bank confirms them
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0023 - Model-derived records are unconfirmed until a human or the bank confirms them

## Context

A model turns "coffee 350" into a balanced transaction by inferring things
nobody said: which merchant, which category, which account. It will sometimes
infer wrongly, and the design already accepts that (vision principle 8). What
the design doesn't give anyone yet is a way to say "I have looked at this and it
is right", so a guessed entry and a verified one look the same in the books.

The owner wants the obvious remedy: the agent records, and he reviews and
approves in the app.

That also resolves a tension in ADR 0016. Editing recorded transactions is
admin-only, so a typo by a member who isn't an admin needed a notification, a
reply and a correction: three messages and a wait. A review pass is where that
correction naturally belongs.

The danger is equally clear, and it's why this needs a decision rather than a
feature. An approval queue that grows faster than anyone drains it is worse than
no approval at all, because it turns into a permanent guilty backlog, everything
in it eventually gets rubber-stamped unread, and the state then means nothing.

## Decision

Every transaction carries a **confirmation state**, `unconfirmed` or
`confirmed`, with who confirmed it, when, and by which route.

### What needs confirming, and what does not

- Model-derived records start unconfirmed: text captures, photo and voice
  captures, and PDF-derived statement lines (ADR 0013).
- Deterministic records are born confirmed: opening balances, structured
  statement imports (CAMT.053, CSV), and anything an admin enters or edits by
  hand. There is nothing for a human to second-guess in a parsed XML amount.

Confirmation sits beside provenance instead of replacing it. Provenance says how
good the source was, and confirmation says whether a human has vouched for the
record, so a provisional PDF line that somebody reviewed is confirmed and still
provisional, and both facts stay visible.

### Three routes to confirmed, and two of them are not work

1. Review in the app. A queue of unconfirmed transactions, newest first,
   designed for a thumb: each row shows the amount, merchant, category and
   account with the inferred fields marked, and the actions are approve, fix or
   delete. Batch approval is the primary action, so you select many and approve
   once. Fixing happens inline, and it is the same edit an admin-only correction
   would be, so the review pass is also the correction pass.
2. The bank confirms it. A transaction matched to an authoritative statement
   line during reconciliation becomes confirmed automatically. That is the
   strongest confirmation available, stronger than a human glance, and it means
   the monthly import drains most of the queue by itself.
3. Silence, but only where it is safe. A capture is auto-confirmed after a quiet
   period when all of these hold: the merchant was already known, the category
   came from the merchant's default rather than from the model, the amount is
   below a configured threshold, and nobody has touched it. Everything else
   waits for route 1 or 2.

Route 3 is what keeps the queue finite, and we made its conditions conservative
on purpose so that it auto-confirms boring repetitions and never a guess.

### Rules that keep the state honest

- Unconfirmed transactions count in the books, so balances and reports include
  them, because a ledger that lags reality is useless. Reports show the
  unconfirmed share for the period, so you can trust a number in proportion.
- Confirming changes nothing financial. It says that somebody reviewed the
  record, and it never moves an amount or an account.
- Any member can confirm their own capture, because that isn't editing a
  financial fact. It's the narrow, safe answer to ADR 0016's collision with "a
  wrong entry must be cheap to fix": you can vouch for what you entered, and
  correcting it stays the owner's.
- Editing an unconfirmed record needs no approval round trip. Whether that
  window should also be time-bounded, in minutes rather than "until someone
  vouches for it", is an open question on spec 0003.
- The queue has a ceiling, and reaching it raises an alert. When unconfirmed
  items older than a configured age pass a threshold, the admins are told once,
  because a queue nobody drains is a process failure and not a data state.
- Confirmation is audited like every other change (ADR 0008): who vouched, when,
  and by which route.

## Alternatives

| Option | Why rejected |
|---|---|
| No confirmation state, as before | A guessed entry and a verified one look identical, so the only way to trust a total is to re-read every row |
| Hold unconfirmed records out of the books until approved | Balances would disagree with reality until somebody did paperwork, and a household captures instantly in order to have the number now |
| Confirm one transaction at a time, modally | The interaction that guarantees nobody drains the queue. Batch approval is the feature and not a refinement of it |
| Auto-confirm everything after a timeout | Makes the state a formality, because everything becomes confirmed whether or not anyone looked, so it stops meaning anything |
| Never auto-confirm anything | The purist position, and it produces the unbounded backlog this ADR exists to prevent. A human adds nothing to a boring repetition at a known merchant |
| Use model confidence as the state | A model's confidence isn't a human's judgement and isn't well calibrated. It can inform route 3's conditions, and it can't stand in for them |
| Reuse the provisional/authoritative distinction | Confuses source quality with review. A deterministic CSV line is authoritative and can still be worth a glance, while a reviewed PDF line is checked and still provisional |

## Consequences

**Good:**
- You can trust a total in proportion, because the unconfirmed share is visible
  instead of hidden.
- The review pass is the correction pass, which removes ADR 0016's round trip of
  notifications and gives members who aren't admins a way to get things fixed in
  one place, quickly.
- Reconciliation drains most of the queue automatically, so the manual load
  falls as the books get more complete instead of rising with volume.
- Auto-confirmation makes the merchant registry pay off twice, because a known
  merchant costs neither a model call nor a review.

**Bad, and the price we accept:**
- The household gains a new recurring chore. Three mechanisms bound it, and it
  is still a chore, and the admins still do most of it.
- The interface has to show two quality dimensions, provenance and confirmation,
  without confusing anyone. The design system carries that (ADR 0022), and it is
  the likeliest place for the interface to get muddy.
- The auto-confirmation thresholds are judgement calls that will be wrong at
  first, and tuning them means tuning how much the household trusts the books.
- Every report now needs the unconfirmed share next to its figure, which is one
  more thing on a small screen.

**What becomes harder to change later:** what `confirmed` means in historical
data. If the auto-confirmation rules change, old rows were confirmed under
different ones, so we record the route per row and reports can tell "a person
looked" from "the bank agreed" from "it was quiet".
