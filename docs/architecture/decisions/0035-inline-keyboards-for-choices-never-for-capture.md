---
id: 0035
title: The bot offers inline buttons for choices and confirmations, never for capture
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0035 - The bot offers inline buttons for choices and confirmations, never for capture

## Context

Everything the bot does today is a sentence, in both directions. That works for
capture, because "coffee 350" beats any interface, and it fails for the other
half of the conversation. Confirming a record, correcting a category, answering
"which project is this for", picking a period for a report: each of those is a
choice among options the system already knows, and typing one out is slower, more
error-prone, and in Russian a lot more typing than a tap.

Telegram provides inline keyboards for exactly this. Without them the household
types "да" a hundred times a year, and every clarifying question invites a
free-text answer the agent then parses, which costs a model call and adds one
more way to be misunderstood for a question with three possible answers.

The risk is just as clear: buttons are how a chat interface becomes a form, one
convenience at a time, and this product exists not to be a form (vision principle
1).

## Decision

The bot uses buttons to choose among what the system already knows, and never to
enter what it doesn't.

We expect buttons in five places. Confirming a record offers approve, fix, and
delete on the confirmation message. A closed question the agent asked - which
category, which account, which project, is this one expense or two - offers the
options the agent would otherwise have listed in prose. A report offers a period
or a dimension, such as this month, last month, or a category from the top few.
An alert offers acknowledge, show me, and remind me after the weekend. And a list
of unconfirmed records or flagged lines offers paging.

Three kinds of keyboard are forbidden. No keyboard captures an expense: no amount
pads, no merchant pickers, no "add expense" button, because capture is a
sentence, a photo, or a voice note. No menu acts as navigation, because a
persistent bottom menu of features makes the bot an app with a bad layout and the
app already exists (ADR 0007). And no message carries more than a handful of
buttons, because a long list is a screen and the app is where screens live.

Five rules keep the line where we drew it. Every button has a typed equivalent,
so anyone can answer in words instead and a member who replies "35 не 350" is
understood exactly as before; the buttons accelerate the answer without ever
being the only path. A stale button is inert: tapping a confirmation on a record
that has changed since says so instead of re-applying. Labels appear in the
member's language and carry no accounting vocabulary. A button never performs a
structural change without the restatement ADR 0031 requires, because the tap is
the agreement and the restatement still comes first. And buttons don't replace
the audit record: the acting member is the one who tapped.

## Alternatives

| Option | Why rejected |
|---|---|
| Text only, as before | Pure, and it makes the household type "да" all year and answers to closed questions parseable by a model, which is both slower and less reliable than a tap |
| A persistent menu keyboard of features | Discoverable, and it turns the bot into a small, badly laid-out app, competing with the real one |
| Buttons for capture too - amount pads, merchant lists | The obvious next step, and the end of the product's premise: the whole point is that you do not fill anything in |
| A Telegram mini-app for structured interactions | Real screens inside chat, and it duplicates the household app with a second codebase and a second auth story |
| Custom reply keyboards instead of inline | They replace the member's keyboard, which gets in the way of the thing they actually need to do: type a capture |

## Consequences

Good:
- The common interactions - confirm, categorise, pick a period - take one tap
  instead of a sentence, in either language.
- Closed questions no longer need a model call to interpret an answer, which
  costs less and can't be misread.
- Misunderstandings drop, because a tap can't be a typo.

Bad, and the price we accept:
- Every future convenience will look like a button, so this decision is under
  constant pressure toward a form, and the forbidden list is the only thing
  holding the line. Anyone arguing about it has to cite that list rather than
  remember it.
- Each choice now has two paths, tapped and typed, so both need testing, and
  changing an option set leaves stale buttons in old messages.
- Button labels are strings in two languages in the message catalogue, and
  they're the easiest place for accounting vocabulary to leak in.

What becomes harder to change later is the household's habits. Once people expect
a tap on confirmations, taking it away feels like a regression, which is a reason
to be conservative about where buttons appear at all.
