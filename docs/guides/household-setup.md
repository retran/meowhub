# Household setup

What the setup conversation asks, in what order, and why (spec 0003, R0-R0f).
An admin starts it by writing something like "let's set up the accounts" or
"настрой счета" to the bot, in a private chat or the household's shared group.

## Why it is a conversation, not a form

A household's real financial shape — which accounts exist, what they hold
today, who pays with what — is exactly the kind of thing that is tedious to
fill into a form and easy to say out loud. The agent asks one question at a
time so nothing is skipped, and because the answers double as the household's
first real bookkeeping (R3): each account's opening balance becomes a real,
balanced transaction the moment it is stated, not a number typed into a
settings screen.

## The steps

1. **Accounts.** For each account — a bank account, a card, a loan, cash —
   the agent asks its name, what kind it is, and what it holds today. A
   credit card or a loan also gets its limit if mentioned. Say "done" (or
   "готово") once there are no more accounts to add.
2. **Household settings.** Timezone and default currency, established once
   for the whole household (R0d) — never assumed from a server's own
   location or a browser's locale.
3. **Default payment account.** Which account is *your own* default when a
   capture does not say how something was paid (R10). Each member sets their
   own.

## It is resumable, and it is safe to leave half-finished

Every answer is written to the database as it is given (ADR 0038), not held
in the workflow engine's memory — a restart, a redeploy, or a crash mid-answer
loses nothing. Ask "what's left to set up?" (or «что осталось настроить?») at
any point to see the remaining steps without losing where you were.

Nothing requires the whole interview to finish before the system is useful
(R0a): the moment the first account and its opening balance exist, a member
can already write "coffee 350" and have it recorded correctly.

## Only an admin can do this

Setting up the books is a structural decision about the household's own
chart of accounts (ADR 0031), so only an admin's request starts or continues
a setup conversation — a non-admin's attempt is refused by the database
itself, not by a check in the bot's own logic (A4).

## Changing something later

Opening a new account, renaming one, or merging two categories outside the
setup flow works the same way: say what you want ("open a Savings account",
"merge groceries and household into groceries"), the agent restates it, and
applies it once you confirm (A3). This, too, is admin-only, for the same
reason.
