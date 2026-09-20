# Household setup

This guide says what the setup conversation asks, in what order, and why (spec
0003, R0-R0f). An admin starts it by writing something like "let's set up the
accounts" or "настрой счета" to the bot, in a private chat or in the household's
shared group.

## Why it is a conversation, not a form

A household's real financial shape - which accounts exist, what they hold today,
and who pays with what - is tedious to fill into a form and easy to say out
loud. The agent asks one question at a time so that you skip nothing, and the
answers double as the household's first real bookkeeping (R3): each account's
opening balance becomes a real, balanced transaction the moment you state it,
instead of a number typed into a settings screen.

## The steps

1. Accounts. For each account, whether a bank account, a card, a loan or cash,
   the agent asks its name, what kind it is, and what it holds today. A credit
   card or a loan also gets its limit if you mention one. Say "done" or
   "готово" once you have no more accounts to add.
2. Household settings. The agent establishes the timezone and the default
   currency once for the whole household (R0d), and never assumes either from a
   server's own location or a browser's locale.
3. Default payment account. The agent asks which account is *your own* default
   when a capture does not say how you paid (R10). Each member sets their own.

## It is resumable, and it is safe to leave half-finished

The agent writes every answer to the database as you give it (ADR 0038) and
holds nothing in the workflow engine's memory, so a restart, a redeploy or a
crash mid-answer loses nothing. Ask "what's left to set up?" or «что осталось
настроить?» at any point and the agent lists the remaining steps without losing
where you were.

You do not have to finish the whole interview before the system becomes useful
(R0a). As soon as the first account and its opening balance exist, a member can
write "coffee 350" and have it recorded correctly.

## Only an admin can do this

Setting up the books is a structural decision about the household's own chart of
accounts (ADR 0031), so only an admin's request starts or continues a setup
conversation. When a member who is not an admin tries, the database refuses the
write itself, and no check in the bot's own logic is what stops it (A4).

## Changing something later

Opening a new account, renaming one, or merging two categories outside the setup
flow works the same way. Say what you want, such as "open a Savings account" or
"merge groceries and household into groceries", the agent restates it, and it
applies the change once you confirm (A3). This is admin-only too, for the same
reason.
