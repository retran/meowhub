---
id: 0036
title: Undo is a first-class action, scoped to the actor and always audited
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0036 - Undo is a first-class action, scoped to the actor and always audited

## Context

The product asks people to act quickly and then trusts a model to interpret them,
and both of those produce mistakes: a capture meant for the card that went to the
current account, a correction applied to the wrong record, a category merge that
turned out to be two different shops after all, an import applied to the wrong
month.

Each mistake already has a repair - an admin can edit, and an import can be
reversed - but the repair is a different action from the one that caused it, so
the person has to work out which repair applies. The system can't yet answer the
cheapest sentence in any interface: "undo that".

The audit log already holds what we need for it, because it records every change
with its before and after image and its actor (ADR 0008). Nothing exposes that to
a member.

## Decision

We make undo an action of its own, available in chat and in the app, over the
last thing the asker did.

Undo is scoped to the actor's own most recent action rather than the household's.
One member's "undo" never reverses another member's work, and it never reaches
further back than their own last action unless they name what to undo. A member
can undo a capture, a correction, a confirmation, a classification change, a
merchant or category merge, a structural change to the chart, and an import,
which ADR 0013 already made reversible as a unit.

Undo is a new, forward change - a compensating action - and it never rewrites
history: the audit log gains a row saying what was undone, by whom, and when,
while the original rows stay exactly as they were. It's also idempotent and
bounded, so undoing twice doesn't undo something else and no unbounded undo stack
exists; reaching anything older means naming it instead of tapping repeatedly.

Undo respects permissions (ADR 0016). A member can undo their own capture or
classification, and only an admin can undo an admin's correction, a merge, or an
import, so undo is never a way around a permission. A destructive undo restates
first: reversing an import or a merge affects many rows, so the agent says what
it's about to reverse and waits, as it does for structural changes (ADR 0031).
The confirmation message carries an undo button (ADR 0035), because people notice
a mistake while that message is still on screen.

## Alternatives

| Option | Why rejected |
|---|---|
| No undo; use the existing repairs | What we had. It makes the cheapest sentence in the interface - "no, undo that" - the one thing the system cannot do, and leaves a member to work out which of several repairs applies |
| A full undo stack, repeatable back through history | Familiar from editors, and dangerous here: tapping undo four times in a shared ledger is a way to silently reverse someone else's work. Scoping to the actor's last action is what makes it safe |
| Rewriting history instead of compensating | Simpler to reason about for one step, and it breaks the append-only audit log (ADR 0008), which is the thing that makes any of this recoverable |
| Undo only in the app | The mistakes happen in chat, seconds after a capture. Making the fix require a different surface is how it stops being used |
| A timed window, after which no undo | Arbitrary: a misfiled import is often noticed weeks later, and the compensating-action model makes age irrelevant |

## Consequences

Good:
- The most common mistakes get the fastest possible repair, in the surface where
  people make them.
- Undo reuses machinery we already have, the audit log and import reversal, so it
  costs exposure rather than construction.
- Vision principle 8 ("a wrong entry must be cheap to fix") no longer depends on
  knowing which repair to reach for.

Bad, and the price we accept:
- Every mutating action now needs a defined inverse, including ones we add later.
  That's a standing requirement on future slices, and the place we'll forget it
  is a feature that writes several kinds of row at once.
- Compensating actions make the audit log longer and a transaction's history
  harder to read at a glance, which is what we pay for never rewriting it.
- "Undo" is ambiguous in a shared system, so the actor-scoped rule will sometimes
  surprise someone who expected it to reverse what they were looking at instead
  of what they last did.

What becomes harder to change later is the scope rule, because widening it to
"the last thing that happened" once people are used to it meaning their own would
silently change what a familiar word does.
