---
id: 0036
title: Undo is a first-class action, scoped to the actor and always audited
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0036 — Undo is a first-class action, scoped to the actor and always audited

## Context

The product asks people to act quickly and then trusts a model to interpret them.
Both of those produce mistakes: a capture meant for the card that went to the
current account, a correction applied to the wrong record, a category merge that
turned out to be two different shops after all, an import applied to the wrong
month.

Each of those already has a repair — an admin can edit, an import can be reversed
— but the repair is a different action from the one that caused it, and the person
has to work out which. What is missing is the cheapest possible sentence in any
interface: **"undo that"**.

The audit log already holds everything needed to do it: every change with its
before and after image and its actor (ADR 0008). The capability exists; nothing
exposes it.

## Decision

**Undo is an action of its own, available in chat and in the app, over the last
thing the asker did.**

- **Scope: the actor's own most recent action**, not the household's. "Undo" from
  one member never reverses another member's work, and never reaches further back
  than their own last action without them naming what to undo.
- **What can be undone**: a capture, a correction, a confirmation, a
  classification change, a merchant or category merge, a structural change to the
  chart, and an import (which ADR 0013 already made reversible as a unit).
- **Undo is a new, forward change** — a compensating action, never a rewrite of
  history. The audit log gains a row saying what was undone, by whom, when; the
  original rows stay exactly as they were.
- **It is idempotent and bounded**: undoing twice does not undo something else,
  and there is no unbounded undo stack. Anything older is reached by naming it,
  not by tapping repeatedly.
- **It respects permissions** (ADR 0016): a member can undo their own capture or
  classification; only an admin can undo an admin's correction, a merge or an
  import. Undo is not a way around a permission.
- **A destructive undo restates first.** Reversing an import or a merge affects
  many rows, so the agent says what it is about to reverse and waits, as it does
  for structural changes (ADR 0031).
- **The button exists** on the confirmation message (ADR 0035), because the moment
  a mistake is noticed is the moment the message is still on screen.

## Alternatives

| Option | Why rejected |
|---|---|
| No undo; use the existing repairs | What we had. It makes the cheapest sentence in the interface — "no, undo that" — the one thing the system cannot do, and leaves a member to work out which of several repairs applies |
| A full undo stack, repeatable back through history | Familiar from editors, and dangerous here: tapping undo four times in a shared ledger is a way to silently reverse someone else's work. Scoping to the actor's last action is what makes it safe |
| Rewriting history instead of compensating | Simpler to reason about for one step, and it breaks the append-only audit log (ADR 0008), which is the thing that makes any of this recoverable |
| Undo only in the app | The mistakes happen in chat, seconds after a capture. Making the fix require a different surface is how it stops being used |
| A timed window, after which no undo | Arbitrary: a misfiled import is often noticed weeks later, and the compensating-action model makes age irrelevant |

## Consequences

**Good:**
- The fastest possible repair for the most common mistakes, in the surface where
  they are made.
- It reuses machinery that already exists — the audit log, import reversal — so
  the cost is exposure rather than construction.
- Vision principle 8 ("a wrong entry must be cheap to fix") stops depending on
  knowing which repair to reach for.

**Bad, and the price we accept:**
- **Every mutating action now needs a defined inverse**, including ones added
  later. That is a standing requirement on future slices, and the place it will be
  forgotten is a feature that writes several kinds of row at once.
- Compensating actions make the audit log longer and the history of a transaction
  harder to read at a glance — the price of never rewriting it.
- "Undo" is ambiguous in a shared system, and the actor-scoped rule will
  occasionally surprise someone who expected it to reverse what they were looking
  at rather than what they last did.

**What becomes harder to change later:** the scope rule. Widening it to "the last
thing that happened" after people are used to it being their own would silently
change what a familiar word does.
