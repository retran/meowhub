# Talking to Meow

This guide says what a household member can write to the bot, in either English
or Russian (ADR 0017), and what happens next. Every example here works as shown.
The wording is not sacred, and what the agent looks for is the shape: an amount,
and whatever else you happen to mention.

## Recording a spend

The plainest form works: an amount and, ideally, where it went.

- `coffee 350` / `кофе 350` - a bare number means minor units of the
  household's currency, so this is 3.50 and not 350.00.
- `groceries 24,40 albert heijn` - the agent reads a decimal comma correctly,
  and it recognises a merchant it has seen before however you spell it.
- `dinner 45 on the credit card` - naming how you paid posts against that
  account instead of your own default.
- `coffee 350 yesterday` - the agent uses a date in the past exactly as you
  state it.
- `45 CHF, charged 42 euros` - a foreign-currency charge keeps both the
  original amount and the euro amount you were actually charged.
- `кофе 350, подарок Маше` - the agent keeps anything after the amount that
  reads as a note, such as "подарок", "gift for" or "for the office", with the
  transaction.

When your message does not say enough, because it carries no recoverable amount
or names a payment method the household does not have, Meow asks exactly one
question and waits. He never asks the same question twice without something new
to go on. Answer it and the capture finishes, and if your answer still leaves a
gap, he asks a further question about something else.

## After a capture

The confirmation carries three quick actions, which you can take as buttons or
as words:

- Approve, or `confirm`, with the same outcome either way.
- Fix category, or `put it under transport`. Reclassifying is not a financial
  correction, so any member can do it to any transaction and not only to their
  own.
- Undo, or `undo`, which reverses *your own* last action as a new, compensating
  entry. It never reaches another member's last action, and it erases nothing
  already written.

## Correcting something already recorded

- `it was 35 not 350` corrects the amount of your most recent capture, or, if
  you are an admin, of the household's most recent one. If you did not capture
  it, or it is already confirmed, Meow files the correction as a request and
  tells the admins, instead of failing without saying so.
- `it was actually at Albert Heijn` corrects the merchant the same way.
- `delete it` works for an admin only, and changes nothing when a member tries
  it.

## Conveniences

- `same again` / `как обычно` repeats your last capture exactly: the same
  amount, category and account, dated today, and unconfirmed.
- `my recent expenses` / `recent captures` returns a short list of what you have
  recorded lately (`list_recent_captures`).
- `remember: use cash` keeps a standing preference that Meow considers on later
  captures, until an admin removes it. A preference is never a financial fact on
  its own.
- `unconfirmed` / `неподтверждённые` works for an admin only, and lists what is
  still waiting for review (`list_unconfirmed`). `confirm all` clears the whole
  list in one reply.

## What you can ask

The list below is the contract (spec 0004, R2/R2a/R23), so Meow refuses a
question outside it plainly and names what you can ask instead, rather than
guessing at an answer. Every entry names the tool behind it, because the tool
names are what stay current as later slices add more: a figure the app can show
and the bot cannot answer would be a regression.

Spending:
- "how much did we spend this month" - `spend_total`
- "what did we spend the most on last month" / «на что мы тратили больше
  всего в том месяце», ranked or for one category by name -
  `spend_by_category`
- "how has groceries spending changed over time" - `spend_by_category_trend`
- "how much at Albert Heijn this year", or every merchant, ranked -
  `spend_by_merchant`
- "how has spending at NS changed over time" - `spend_by_merchant_trend`
- "what did I spend this month" / "what did everyone spend" -
  `spend_by_member`
- "how has my spending changed over time" - `spend_by_member_trend`

The accounts:
- "what's in the ABN AMRO account" / "what's our headroom on the credit
  card" - `account_balance`
- "what do we have in total" / "what's our net position" -
  `household_position`
- "how much do we owe in total" / "how much on the credit card" -
  `liability_summary`
- "what happened on the credit card this month" - `account_movement`
- "what were the biggest expenses last month" - `largest_expenses`
- "how many things are waiting for review" - `unconfirmed_summary`

Finding a specific record:
- "find the transaction with 'Маше' in it" / `search transactions for ...` -
  `search_transactions`
- "why is this categorised as transport" - `why_category`

Taking the books with you:
- "export last month" - `export_period`. The CSV arrives in the chat as a
  file, one row per posting, with the account, amount, merchant, note and
  confirmation state. Any member can ask for it, because everyone can already
  read the whole ledger and an export is the same reading in bulk.

## The digests you are sent without asking

Meow sends two digests on his own:

- A weekly digest every Monday morning, covering the last seven days.
- A monthly digest on the 1st, covering the month that closed.

Each one carries the period's total, the largest categories, the previous
period's figure, how much of the total is still unconfirmed, and whether anyone
has checked the period against the bank. It carries nothing else: no advice and
no comment. Meow sends a digest for an empty period too, in one line, so that
silence from him always means something is broken and never that nobody spent
anything.

Tell Meow to stop sending you either digest and he will. The preference is yours
alone and changes nothing for anybody else in the household.

## What Meow will not do

He never creates an account you did not ask for, he never guesses where a
question would resolve the ambiguity instead, and he never comments on how the
household spends its money (`docs/standards/agent-persona.md`).
