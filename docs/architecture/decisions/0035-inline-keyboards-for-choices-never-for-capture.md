---
id: 0035
title: The bot offers inline buttons for choices and confirmations, never for capture
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0035 — The bot offers inline buttons for choices and confirmations, never for capture

## Context

Everything the bot does is currently a sentence, in both directions. That is
right for capture — "coffee 350" is faster than any interface — and wrong for the
other half of the conversation. Confirming a record, correcting a category,
answering "which project is this for", picking a period for a report: each of
these is a **choice among known options**, and typing one out is slower, more
error-prone, and in Russian considerably more typing than a tap.

Telegram provides inline keyboards for exactly this. Not using them means the
household types "да" a hundred times a year, and that every clarifying question
invites a free-text answer the agent then has to parse — a model call, and a new
way to be misunderstood, for a question with three possible answers.

The risk is equally clear. Buttons are how a chat interface turns into a form,
one convenience at a time, and a form is what this product exists not to be
(vision principle 1).

## Decision

**Buttons are for choosing among what the system already knows. Never for
entering what it does not.**

Allowed, and expected:

- **Confirming a record**: approve, fix, delete, on the confirmation message.
- **Answering a closed question the agent asked**: which category, which account,
  which project, is this one expense or two — the options being the ones the
  agent would otherwise have listed in prose.
- **Choosing a period or a dimension** for a report: this month, last month,
  a category from the top few.
- **Acting on an alert**: acknowledge, show me, remind me after the weekend.
- **Paging** a list of unconfirmed records or flagged lines.

Forbidden:

- **Any keyboard that captures an expense.** No amount pads, no merchant pickers,
  no "add expense" button. Capture is a sentence, a photo or a voice note.
- **Menus as navigation.** No persistent bottom menu of features: it makes the
  bot an app with a bad layout, and the app already exists (ADR 0007).
- **More than a handful of buttons at once.** A long list is a screen; if the
  answer needs a screen, the app has one.

Rules that keep it honest:

- **Every button has a typed equivalent.** Anyone can answer in words instead,
  always — the buttons are an accelerator, never the only path, and a member who
  replies "35 не 350" is understood exactly as before.
- **A stale button is inert.** Tapping a confirmation on a record that has since
  been changed says so rather than re-applying.
- **Labels are in the member's language** and carry no accounting vocabulary.
- **A button never performs a structural change without the restatement**
  ADR 0031 requires — the tap is the agreement, and the restatement still precedes
  it.
- **Buttons do not replace the audit record**: the acting member is the one who
  tapped.

## Alternatives

| Option | Why rejected |
|---|---|
| Text only, as before | Pure, and it makes the household type "да" all year and answers to closed questions parseable by a model, which is both slower and less reliable than a tap |
| A persistent menu keyboard of features | Discoverable, and it turns the bot into a small, badly laid-out app, competing with the real one |
| Buttons for capture too — amount pads, merchant lists | The obvious next step, and the end of the product's premise: the whole point is that you do not fill anything in |
| A Telegram mini-app for structured interactions | Real screens inside chat, and it duplicates the household app with a second codebase and a second auth story |
| Custom reply keyboards instead of inline | They replace the member's keyboard, which gets in the way of the thing they actually need to do: type a capture |

## Consequences

**Good:**
- The common interactions — confirm, categorise, pick a period — become one tap
  rather than a sentence, in either language.
- Closed questions stop needing a model call to interpret an answer, which is
  cheaper and cannot be misread.
- Fewer misunderstandings: a tap cannot be a typo.

**Bad, and the price we accept:**
- **Constant pressure toward a form.** Every future convenience will look like a
  button, and the forbidden list is the only thing holding the line. It has to be
  cited, not remembered.
- Two paths for every choice — tap and typed — so both need testing, and a
  changed option set means stale buttons in old messages.
- Button labels are strings in two languages, in the message catalogue, and they
  are the easiest place for accounting vocabulary to leak in.

**What becomes harder to change later:** the household's habits. Once a tap is
expected on confirmations, removing it would feel like a regression — which is a
reason to be conservative about where buttons appear in the first place.
