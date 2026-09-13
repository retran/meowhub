---
id: 0037
title: Keyboard-first on desktop — a command palette, single-key actions, no mouse-only path
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0037 — Keyboard-first on desktop: a command palette, single-key actions, no mouse-only path

## Context

Desktop exists in this product for one reason: it is where an admin does the
work — draining the confirmation queue, going through what an import flagged,
fixing the chart of accounts, merging merchants (`docs/design/screens.md`). All
of it is repetitive, and all of it is currently designed as pointing and
clicking.

The owner wants the interaction model **Linear** popularised: a command palette
as the way to reach anything, unmodified single keys for actions in context,
list navigation that never needs the mouse, and shortcuts that are discoverable
rather than folklore. It is the right model for this work — approving twelve
records is twelve keystrokes or twelve aimed clicks, and the difference is
whether the queue gets drained.

It is also a model with a narrow audience, and pretending otherwise would damage
the product. The household is two admins with laptops and a teenager with a
phone. Nobody is going to learn `g` then `i` to check what they have left.

## Decision

**The desktop app is fully operable from the keyboard, and the phone is
untouched by it.**

### The model

- **A command palette** on `⌘K` / `Ctrl+K` is the way to reach anything: every
  screen, and every action available in the current context. It is the one thing
  a person has to learn, and it teaches the rest — each entry shows its own
  shortcut beside it.
- **Unmodified single keys act in context**, the way Linear does: with a row
  focused in the queue, one key approves, one opens it, one corrects, one undoes.
  The set is small and consistent across lists.
- **Sequences for navigation** — `g` then a letter — so moving between screens
  never needs a modifier or the mouse.
- **`/` focuses search**, `?` opens the shortcut map, `Escape` always backs out
  one level, `⌘Z` undoes (ADR 0036 already made undo a first-class action, which
  is what makes a fast keyboard path safe).
- **Arrow keys and `j`/`k` both move** through any list; `Space` selects;
  `Shift` extends a selection; `Enter` performs the row's primary action.

### The rules that make it real rather than decorative

- **No action anywhere on desktop may be reachable only by mouse.** A screen
  with a mouse-only affordance is incomplete, and it is checked, not trusted.
- **Every screen declares its keys** in its design, in the design document, and
  in the `?` overlay. An undiscoverable shortcut is folklore, not an interface.
- **Focus is never lost.** After any action — approve, correct, delete, undo —
  focus lands somewhere deliberate and visible, usually the next row. A keyboard
  model that drops focus after each action is slower than clicking.
- **Focus is always visible**, and its ring is part of the design system
  (ADR 0022), not a browser default.
- **The palette respects permissions.** It offers a member only what a member may
  do (ADR 0016); authorisation stays in the database (ADR 0014) and the palette
  is a view of it, never a second gate.
- **The palette is fed from the same views and actions as the screens.** It is a
  different way in, never a parallel feature set.
- **Shortcuts are not configurable.** One household, one map; a rebinding layer
  is a feature nobody here needs and a source of inconsistency in the help
  overlay.

### What this does not touch

- **The phone.** It keeps thumb-first targets of at least 44 px, no chrome for
  shortcuts, no palette. A phone keyboard is for typing a capture into the chat,
  and nothing on the phone may be designed around keys.
- **The bot.** Chat is its own interaction model, with inline buttons for choices
  (ADR 0035).
- **Screen-reader and accessibility requirements**, which stand on their own
  (ADR 0022): keyboard operability is necessary for them and not the same thing —
  a fast power-user path can still be unusable with a screen reader if roles and
  labels are wrong.

## Alternatives

| Option | Why rejected |
|---|---|
| Mouse-first with a few shortcuts added | Where most apps land, and it makes the repetitive work — the entire reason desktop exists here — as slow as it is on the phone |
| A command palette only, without per-row keys | Half the model: a palette is for reaching things, and approving a row should not cost two keystrokes plus reading a list |
| Per-row keys only, without a palette | Fast once learned and undiscoverable before that. The palette is what makes the rest learnable without a manual |
| Vim-style modal editing | More powerful and much steeper; this is a household ledger, not an editor, and the second admin has to be able to use it |
| Configurable keybindings | A preference layer, a settings screen, and a help overlay that can no longer state the truth, for a household of three |
| The same keyboard model on the phone | There is no keyboard to speak of, and the affordances it would need — shown shortcuts, focus rings, dense rows — would spoil the surface that has to work with a thumb |

## Consequences

**Good:**
- The work desktop exists for gets genuinely fast: a queue of twelve is a dozen
  keystrokes without leaving the home row.
- The palette makes the app discoverable without a menu bar, and gives every
  action one canonical name — which is also useful when writing the guide.
- Keyboard operability is a hard requirement rather than an accessibility
  afterthought, so the two reinforce each other.
- Undo being first-class (ADR 0036) is what makes a single keystroke safe to
  give an action.

**Bad, and the price we accept:**
- **This is real application complexity**: a command registry, a focus model, a
  shortcut map, an overlay, and selection state that survives updates. It is the
  largest single addition to a component ADR 0007 deliberately kept thin, and it
  makes "a few screens of fetch and layout" less true than it was.
- The model expects the app to feel instant, which pushes toward optimistic
  updates and prefetching — more state in the client than a read-only app needs.
- Two interaction models to keep coherent, and every new desktop screen now owes
  a key map.
- Only two people will ever use it. That is a deliberate trade: those two people
  do all the work the system needs.

**What becomes harder to change later:** the key map itself, once the admins have
it in their fingers — which is an argument for keeping it small and conventional
rather than clever.
