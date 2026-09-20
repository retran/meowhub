---
id: 0037
title: Keyboard-first on desktop — a command palette, single-key actions, no mouse-only path
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0037 - Keyboard-first on desktop: a command palette, single-key actions, no mouse-only path

## Context

Desktop exists in this product so that an admin can do the repetitive work:
draining the confirmation queue, going through what an import flagged, fixing
the chart of accounts, and merging merchants (`docs/design/screens.md`). All of
that work was designed as pointing and clicking, which is why approving twelve
records costs twelve aimed clicks today.

The owner wants the interaction model Linear made popular, because it fits this
kind of work: a command palette as the way to reach anything, unmodified single
keys for actions in context, list navigation that never needs the mouse, and
shortcuts a person can discover in the app instead of learning from another
admin. Twelve approvals become twelve keystrokes, and that difference decides
whether the queue gets drained at all.

The same model has a narrow audience here, and the owner doesn't want to pretend
otherwise. The household is two admins with laptops and a teenager with a phone,
and the teenager will never learn `g` then `i` to check what's left for her.

## Decision

The desktop app is fully operable from the keyboard, and the phone keeps the
interaction model it already has.

### The model

- A command palette on `⌘K` / `Ctrl+K` reaches anything: every screen, and every
  action available in the current context. It's the one thing an admin has to
  learn, and it teaches the rest, because each entry shows its own shortcut
  beside it.
- Unmodified single keys act in context, the way Linear does. With a row focused
  in the queue, one key approves it, one opens it, one corrects it, and one
  undoes it. The set stays small and means the same thing in every list.
- Sequences move between screens: `g` then a letter, so navigation needs neither
  a modifier nor the mouse.
- `/` focuses search, `?` opens the shortcut map, `Escape` backs out one level,
  and `⌘Z` undoes. ADR 0036 already made undo a first-class action, which is
  what makes a fast keyboard path safe to offer.
- Arrow keys and `j`/`k` both move through any list, `Space` selects, `Shift`
  extends a selection, and `Enter` performs the row's primary action.

### The rules that make it real rather than decorative

- No action anywhere on desktop is reachable only by mouse. A screen with a
  mouse-only affordance is incomplete, and a check enforces this instead of
  trusting the author.
- Every screen declares its keys in its design, in the design document, and in
  the `?` overlay, so that no shortcut survives only in an admin's memory.
- Focus is never lost. After approving, correcting, deleting, or undoing, focus
  lands somewhere deliberate and visible, usually the next row, because a model
  that drops focus after each action ends up slower than clicking.
- Focus stays visible, and its ring comes from the design system (ADR 0022)
  instead of the browser default.
- The palette respects permissions: it offers a member only what a member can do
  (ADR 0016). Authorisation stays in the database (ADR 0014), and the palette
  shows what the database allows without acting as a second gate.
- The palette reads the same views and calls the same actions as the screens, so
  it's a second way in to one feature set.
- Shortcuts aren't configurable. One household means one key map, and a
  rebinding layer would cost a settings screen and leave the help overlay unable
  to state the truth.

### What this does not touch

- The phone. It keeps thumb-first targets of at least 44 px, no chrome for
  shortcuts, and no palette. A phone keyboard is for typing a capture into the
  chat, and nothing on the phone is designed around keys.
- The bot. Chat is its own interaction model, with inline buttons for choices
  (ADR 0035).
- Screen-reader and accessibility requirements, which stand on their own
  (ADR 0022). Keyboard operability is necessary for them but isn't the same
  thing, because a fast power-user path can still be unusable with a screen
  reader when roles and labels are wrong.

## Alternatives

| Option | Why rejected |
|---|---|
| Mouse-first with a few shortcuts added | Where most apps land, and it leaves the repetitive work that desktop exists for as slow as it is on the phone |
| A command palette only, without per-row keys | Half the model: a palette reaches things, and approving a row would still cost two keystrokes plus reading a list |
| Per-row keys only, without a palette | Fast once learned, and undiscoverable before that, because the palette is what makes the keys learnable without a manual |
| Vim-style modal editing | More powerful and much steeper to learn; this is a household ledger, and the second admin has to be able to use it |
| Configurable keybindings | Buys a preference layer, a settings screen, and a help overlay that can no longer state the truth, for a household of three |
| The same keyboard model on the phone | A phone has no keyboard to speak of, and shown shortcuts, focus rings, and dense rows would spoil a screen that has to work with a thumb |

## Consequences

Good:
- The work desktop exists for becomes fast: a queue of twelve costs a dozen
  keystrokes without leaving the home row.
- The palette makes the app discoverable without a menu bar, and it gives every
  action one canonical name, which also helps when writing the guide.
- Keyboard operability becomes a hard requirement instead of an accessibility
  afterthought, so the two reinforce each other.
- Undo is first-class already (ADR 0036), which is what makes it safe to put an
  action behind a single keystroke.

Bad, and the price we accept:
- We're adding real application complexity: a command registry, a focus model, a
  shortcut map, an overlay, and selection state that survives updates. It's the
  largest single addition to a component ADR 0007 deliberately kept thin, and it
  makes "a few screens of fetch and layout" less true than it was.
- The model expects the app to feel instant, which pushes us toward optimistic
  updates and prefetching, so the client holds more state than a read-only app
  needs.
- We now keep two interaction models coherent, and every new desktop screen owes
  a key map.
- Only two people will ever use it, which we accept because those two people do
  all the work the system needs.

What becomes harder to change later is the key map itself, once the admins have
it in their fingers, so we keep it small and conventional instead of clever.
