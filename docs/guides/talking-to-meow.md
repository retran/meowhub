# Talking to Meow

What a household member can say to the bot, in either English or Russian
(ADR 0017), and what happens. Every example here works as shown; the wording
is not sacred, but the shape of it — an amount, and whatever else you happen
to mention — is what the agent looks for.

## Recording a spend

The plainest form works: an amount and, ideally, where it went.

- `coffee 350` / `кофе 350` — a bare number is minor units of the household's
  currency: 3.50, not 350.00.
- `groceries 24,40 albert heijn` — a decimal comma is read correctly, and a
  merchant it has seen before is recognised however it is spelled.
- `dinner 45 on the credit card` — naming how it was paid posts against that
  account instead of your own default.
- `coffee 350 yesterday` — a stated date in the past is used as given.
- `45 CHF, charged 42 euros` — a foreign-currency charge keeps both the
  original amount and the euro amount actually charged.
- `кофе 350, подарок Маше` — anything after the amount that reads as a note
  ("подарок", "gift for", "for the office") is kept with the transaction.

If the message does not say enough — no recoverable amount, or a payment
method the household does not have — Meow asks exactly one question, waits,
and never asks the same one twice without something new to go on. Answer it
and the capture finishes; if the answer still leaves a gap, a further,
different question follows.

## After a capture

The confirmation carries three quick actions, as buttons or as words:

- **Approve** / `confirm` — same outcome either way.
- **Fix category** / `put it under transport` — reclassifying is never
  treated as a financial correction, so any member can do this to any
  transaction, not only their own.
- **Undo** / `undo` — reverses *your own* last action as a new, compensating
  entry. It never reaches another member's last action, and nothing already
  written is erased.

## Correcting something already recorded

- `it was 35 not 350` — corrects the amount of your most recent capture (or,
  for an admin, the household's most recent one). If you are not the one who
  captured it, or it is already confirmed, the correction is filed as a
  request and the admins are told, rather than silently failing.
- `it was actually at Albert Heijn` — corrects the merchant the same way.
- `delete it` — admin only; a member's attempt changes nothing.

## Conveniences

- `same again` / `как обычно` — repeats your last capture exactly: same
  amount, category and account, dated today, unconfirmed.
- `my recent expenses` / `recent captures` — a short list of what you have
  recorded lately (`list_recent_captures`).
- `remember: use cash` — keeps a standing preference Meow considers on later
  captures, until an admin removes it. Never a financial fact by itself.
- `unconfirmed` / `неподтверждённые` — admin only: lists what is still
  waiting for review (`list_unconfirmed`); `confirm all` clears the whole
  list in one reply.

## What you can ask

This is the contract (spec 0004, R2/R2a/R23): a question outside this list is
refused plainly, naming what can be asked instead, rather than guessed at.
Every entry names the tool behind it, because that is what stays current as
later slices add more — a figure the app can show but the bot cannot answer
would be a regression.

**Spending:**
- "how much did we spend this month" — `spend_total`
- "what did we spend the most on last month" / «на что мы тратили больше
  всего в том месяце» (ranked, or one category by name) — `spend_by_category`
- "how has groceries spending changed over time" — `spend_by_category_trend`
- "how much at Albert Heijn this year" (or every merchant, ranked) —
  `spend_by_merchant`
- "how has spending at NS changed over time" — `spend_by_merchant_trend`
- "what did I spend this month" / "what did everyone spend" —
  `spend_by_member`
- "how has my spending changed over time" — `spend_by_member_trend`

**The accounts:**
- "what's in the ABN AMRO account" / "what's our headroom on the credit
  card" — `account_balance`
- "what do we have in total" / "what's our net position" —
  `household_position`
- "how much do we owe in total" / "how much on the credit card" —
  `liability_summary`
- "what happened on the credit card this month" — `account_movement`
- "what were the biggest expenses last month" — `largest_expenses`
- "how many things are waiting for review" — `unconfirmed_summary`

**Finding a specific record:**
- "find the transaction with 'Маше' in it" / `search transactions for ...` —
  `search_transactions`
- "why is this categorised as transport" — `why_category`

**Taking the books with you:**
- "export last month" — `export_period`. The CSV arrives in the chat as a
  file: one row per posting, with the account, amount, merchant, note and
  confirmation state. Any member can ask — everyone can already read the
  whole ledger, so an export is only the same reading in bulk.

## The digests you are sent without asking

- A **weekly** digest every Monday morning, covering the last seven days.
- A **monthly** digest on the 1st, covering the month that closed.

Each carries the period's total, the largest categories, the previous
period's figure, how much of it is still unconfirmed, and whether the period
has been checked against the bank. Nothing else — no advice and no comment.
A period with nothing in it is still sent, in one line, so silence always
means something is broken rather than that nothing was spent.

Tell Meow to stop sending you either one and he will; the preference is
yours alone and does not affect anybody else in the household.

## What Meow will not do

He never creates an account you did not ask for, never guesses when a
question would resolve the ambiguity instead, and never comments on how the
household spends its money (`docs/standards/agent-persona.md`).
