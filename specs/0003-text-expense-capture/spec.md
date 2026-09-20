---
id: 0003
title: Chart of accounts, opening balances and text expense capture
status: done
created: 2026-09-12
updated: 2026-09-13
owner: owner
supersedes: []
---

# 0003 - Chart of accounts, opening balances and text expense capture

## Problem

Nobody records what the household spends. Spending happens at a till or on a
phone, with no hands free, so a system that asks for an amount, a date, a
category and a payment method at that moment goes unused, which is exactly what
happens today.

A flat list of amounts would not help this household either. With a credit card,
an overdraft and a loan in play, a total that ignores how something was paid for
is wrong in a way nobody notices. The first recording therefore has to be real
bookkeeping already, even though the member who records an expense must never be
asked to know that.

## Why

After this slice, a member writes "coffee 350" to the bot and the household's
books gain a correct, balanced transaction attributed to that member. Opening
balances anchor those books to the real world, so every later slice has
something true to build on.

We will know it worked when more than one member captures expenses over a week
and the resulting account balances move in step with reality.

## Users and scenarios

- **Member** wants to write what they spent in their own words so that it is
  recorded without them stopping what they are doing.
- **Member** wants to be told, briefly, what the bot understood, so they can
  catch a mistake immediately.
- **Member** wants to fix a wrong amount, category or merchant in one message.
- **Owner** wants the books to start from each account's real balance, so that
  totals mean something from the first day.
- **Owner** wants a spending record he can trust not to confuse a card purchase
  with a card payment.

## Requirements

### Setting the books up, conversationally

The household sets up its own books by talking to the bot, because an admin who
has to fill in a schema will not start. These requirements cover that interview
and the state it keeps between messages.

- **R0.** An admin must be able to set the books up by talking to the bot: the
  agent asks what accounts exist, what each holds today, who pays with what, and
  how cash is handled, one question at a time, in a session the admin can pause
  and resume.
- **R0a.** Setup must be usable in parts. Capture must already work after the
  first account and its opening balance, and nothing may require the whole
  interview to be finished first.
- **R0b.** The agent must restate each structural change before applying it, and
  must record the asking admin as the actor (ADR 0031).
- **R0c.** An admin must be able to open, rename, deactivate or re-term an
  account, and to rename, re-parent or merge a category, either in chat or by
  hand. The agent must never create an account unasked.
- **R0d.** The agent must establish the household's timezone and default
  currency in the same conversation rather than assume them.
- **R0e.** The state of a setup conversation must live in PostgreSQL rather than
  in the workflow engine's execution context (ADR 0038), so that a paused setup
  survives a restart, a redeploy and a restore. At most one setup per member can
  be open.
- **R0f.** The system must record a pending question as asked, and must not ask
  it again without new information.

### The books

The ledger is double-entry, and these requirements fix the invariants that make
a balance trustworthy: what an account is, what a transaction is, and what the
system keeps about the message that produced it.

- **R1.** The system must hold a chart of accounts covering whatever the
  household says it has: current accounts, cash, cards, loans, plus income and
  expense accounts and an opening-balance account. Account types are fixed; the
  accounts themselves are data (ADR 0031).
- **R2.** Every recorded economic event must consist of at least two postings
  whose amounts sum to zero, and the system must reject anything that does not.
- **R3.** Each account that holds value must be given its real starting position
  once, recorded as a transaction, so that every balance after that is derived
  and correct.
- **R4.** A debit account must be able to hold a negative balance where the
  household has an overdraft, and must record what its limit is.
- **R5.** The system must derive an account balance from postings and must never
  store it as a maintained figure.
- **R6.** Every transaction must record who submitted it, in what form, when,
  and which model interpreted it, if any.
- **R6a.** The system must store the exact text of the message that produced a
  transaction, link it to that transaction, and return it later exactly as sent,
  rather than let it be inferred from the confirmation reply. Where reaching a
  balanced transaction took more than one message (R17's follow-up questions),
  every message in that exchange is stored and linked to it, in order, not only
  the first one. Spec 0005 gives a photo or voice note the same guarantee in its
  R7: whatever caused a record to exist is itself kept, whichever form it
  arrived in and however many messages it took.
- **R7.** The system must record every change to a transaction with its before
  state, its after state and its actor.

### Capture

Capture turns one free-text message into a balanced transaction. These
requirements cover what the system extracts, what it defaults, how it confirms,
and how a member corrects it afterwards.

- **R7a.** Every recorded transaction must carry a confirmation state, and a
  model-derived one must start unconfirmed (ADR 0023).
- **R7b.** A member must be able to confirm, and to correct, a transaction they
  captured while it is still unconfirmed.
- **R7c.** The system must auto-confirm a transaction after a configured quiet
  period when its merchant was already known, its category came from that
  merchant's default rather than from the model, and its amount is below a
  configured threshold. It must auto-confirm nothing else.
- **R8.** A member must be able to record an expense in one free-text message,
  without naming an account, a date or a category when the defaults are correct.
- **R9.** The system must extract the amount, the date, the merchant and the
  category from that message, and choose which account it was paid from.
- **R10.** When the message does not say how it was paid, the system must use
  that member's default payment account, which is established during setup and
  changeable later.
- **R11.** When the message does not say when, the system must use the current
  date in the household's timezone.
- **R11a.** The system must interpret captures written in Russian or English,
  and must reply in the language that member prefers (ADR 0017).
- **R11b.** The system must store categories and account types as
  language-neutral slugs, and resolve display names per language.
- **R11c.** Extraction must use a prompt held in this repository with a declared
  output schema, and the system must treat a response failing validation as an
  unparsed capture rather than write it partially (ADR 0025).
- **R11cc.** Every action the agent performs must go through a declared tool
  with a validated input schema and the acting member's authority (ADR 0039). A
  call failing validation is an unparsed capture, never a partial write, and a
  tool the acting member is not allowed to use must fail at the database.
- **R11d.** Prompts and schemas must reach the workflows from the repository,
  mounted read-only into the container and referenced by task and version, and
  must never be pasted into workflow JSON. A missing or unreadable prompt must
  fail loudly at startup rather than at the first capture.
- **R12.** The system must recognise a merchant it has seen before from what the
  member typed, however they spelled it, and must record a merchant it has not
  seen before so that it is recognised next time.
- **R13.** The system must classify the expense into a category, preferring the
  merchant's established category over a fresh guess. Where no category fits, it
  must create one and flag it unreviewed (ADR 0031).
- **R14.** The system must confirm what it recorded in one short message, in
  plain language, naming no accounting concepts.
- **R15.** The owner must be able to correct the amount, date, category,
  merchant or payment account of any recorded transaction, in one message
  (ADR 0016).
- **R15a.** Any member must be able to change the category or project
  attribution of any transaction, because classification is not a financial fact
  (ADR 0021).
- **R16.** The owner must be able to delete a transaction, and the deletion must
  remain visible in the audit record.
- **R16a.** A member who wants a financial correction they are not allowed to
  make must be able to ask for it in one message. The system records the request
  against the transaction and notifies the admins.
- **R17.** When the system cannot produce a balanced transaction it trusts, it
  must store what it received and ask the member a question that would resolve
  it, recording nothing until the member answers. If the answer still leaves it
  unable to produce a transaction it trusts, it must ask a further question
  rather than guess, so the exchange is a real back-and-forth and is never
  capped at exactly one round. It never repeats a question already asked and
  answered, and it never asks two things in one message. It stops asking once it
  has enough, and names what it is still missing if the member stops answering.
- **R18.** The system must refuse a message from a Telegram account that is not
  a household member, without disclosing anything about itself.
- **R19.** The same Telegram message delivered more than once must not produce
  more than one transaction, in either delivery mode, because long polling
  re-delivers after a crash just as a webhook retries (ADR 0033).
- **R20.** An admin must be able to list unconfirmed transactions in chat and
  confirm them, so that the queue is drainable before the app exists.
- **R21.** Every capture must receive a confirmation, and that confirmation must
  state only what the system inferred, not what the member already said.
- **R22.** Cash must be a real account: a withdrawal is a transfer into it, and
  cash spending posts against it. The system tracks cash rather than treat it as
  spent on withdrawal.
- **R23.** The confirmation must carry inline buttons for the common next
  actions, which are approve, fix the category and undo, each with a typed
  equivalent (ADRs 0035, 0036).
- **R24.** A member must be able to say "undo" and have their own most recent
  action reversed as a compensating change (ADR 0036).
- **R25.** A member must be able to attach a free-text note to a transaction in
  the same message or afterwards, as in "это подарок Маше", and the system must
  store it with the transaction and make it searchable.
- **R25a.** The agent must be able to keep a standing fact worth carrying into a
  later, unrelated conversation, such as a household preference or a merchant
  quirk it keeps mis-guessing, and must consider what it has kept when composing
  a later reply (ADR 0044). Such a fact is never a financial fact, and it never
  substitutes for asking when the ledger's own invariants need an answer.
- **R26.** A member must be able to repeat their last expense at a merchant
  without restating it, with "как обычно" or "same again", which records the
  same amount, category and account, dated today, unconfirmed.
- **R27.** A member must be able to ask for their recent captures in chat and
  receive a short list with the actions from R23 available on each.
- **R28.** Where an expense was charged in another currency, the system must
  store the original amount and currency alongside the amount charged in EUR,
  because storing it now costs nothing and it cannot be recovered later.
- **R29.** An admin must be able to ask what still needs setting up and receive
  the remaining steps of the setup conversation, so a paused setup is resumable
  without remembering where it stopped.

## Scope

**In scope:**
- The chart of accounts and the balanced-transaction invariant.
- Opening balances for every real account.
- Text capture, merchant recognition and learning, categorisation, defaults.
- Confirming, correcting and deleting a just-recorded transaction.
- Unparsed captures and the single clarifying question.
- Identifying members and refusing strangers.

**Out of scope (and why):**
- Photos and voice notes (spec 0005). Adding a second input form here would make
  this slice's failure modes ambiguous.
- Queries, reports and digests (spec 0004). Recording must be right before
  reading is worth building.
- Statement import and reconciliation (spec 0007), because there is nothing to
  reconcile against yet.
- Card settlement, interest and fees as *flows* (spec 0008). The accounts exist
  here; the recurring mechanics do not.
- Budgets, commitments and planned purchases (spec 0009).
- Any screen (spec 0006). A member makes corrections here in chat.
- Splitting one expense across several categories. This is common in a
  supermarket, and we deferred it until single-category capture is reliable.

## Acceptance criteria

- [x] **A1.** Given an empty ledger, when an admin completes the setup
      conversation, then each account exists with the type they described and its
      derived balance equals the opening balance they gave.
- [x] **A2.** Given a setup conversation abandoned after one account, when a
      capture is sent against that account, then it is recorded, so a partial
      setup leaves a working system.
- [x] **A3.** Given an admin asking the bot to open an account or merge two
      categories, when the agent has restated it and the admin has agreed, then it
      is applied, and the audit row names the admin as the actor.
- [x] **A4.** Given a member who is not an admin asking the bot to open an
      account, when it is attempted, then nothing is created.
- [x] **A5.** Given a cash withdrawal from a bank account, when recorded, then it
      is a transfer into the cash account and the month's spending does not change;
      and when cash is then spent, that is the expense.
- [x] **A6.** Given any attempt to record postings that do not sum to zero, when
      it is written, then the database rejects it, verified by attempting it
      directly and not only through a workflow.
- [x] **A7.** Given a member whose default payment account is a current account,
      when they send "coffee 350", then a transaction is recorded dated today
      that reduces that account by 3.50 and increases an expense account, and
      nothing else changes.
- [x] **A8.** Given the same member, when they send "groceries 24,40 albert
      heijn", then the amount is recorded as 24.40 and the merchant matches the
      existing Albert Heijn merchant despite the lower case.
- [x] **A9.** Given a merchant never seen before, when an expense naming it is
      captured, then the merchant is created, and a later capture spelling it
      differently matches the same merchant.
- [x] **A10.** Given a merchant with an established category, when an expense at
      that merchant is captured with no category stated, then the established
      category is used without consulting a model.
- [x] **A11.** Given a member states the payment method, as in "on the credit
      card", when the expense is captured, then the expense posts against the card
      liability and no bank account is touched.
- [x] **A12.** Given a capture, when the confirmation is sent, then it states the
      amount, merchant and category in plain language, contains none of the words
      "posting", "debit", "credit" or "account", is one line, carries no comment on
      the spending itself, and matches the persona in
      `docs/standards/agent-persona.md`.
- [x] **A13.** Given a just-recorded transaction, when an admin replies "it was
      35 not 350", then the transaction is corrected, the confirmation reflects
      the new amount, and the audit record shows both states and the actor.
- [x] **A14.** Given a transaction a member who is not an admin captured and has since
      confirmed, when that member sends the same correction, then the amount is
      unchanged, a correction request is recorded against the transaction, and the
      admins are notified (R16a), because R7b's own correction window closes at
      confirmation, the same gate `db/tests/013_ledger_row_level_security.sql`
      already proves at the database.

- [x] **A15.** Given any transaction, when a member who is not an admin changes its category
      or project, then the change applies, because classification is not a financial fact.
- [x] **A16.** Given a just-recorded transaction, when an admin deletes it, then
      it no longer affects any balance and the deletion with its final state
      remains in the audit record.
- [x] **A17.** Given any transaction, when a member who is not an admin attempts to delete
      it, then it is not deleted, enforced by row-level security and proven by
      impersonation rather than only through the bot.
- [x] **A18.** Given a message with no recoverable amount, such as "that was
      expensive", when it is captured, then no transaction exists, the message is
      stored, and the member is asked one question.
- [x] **A18a.** Given an unparsed capture whose answer still leaves the amount or
      the merchant unresolvable, when that answer is processed, then a further,
      different question is asked instead of a guess, never the question just
      answered, and the capture stays unparsed, storing every message so far.
- [x] **A19.** Given an unanswered unparsed capture, when the member replies with
      the missing piece, then the transaction is recorded and the capture is
      closed, whether that reply was the first answer or a later one in the
      same exchange.
- [x] **A20.** Given the model gateway is unavailable, when a capture arrives,
      then the message is stored as unparsed, the member is told it will be
      handled, and nothing is recorded or lost.
- [x] **A21.** Given a Telegram account that is not a member, when it messages the
      bot, then no transaction is recorded, the reply reveals nothing, and the
      attempt is logged.
- [x] **A22.** Given one Telegram message delivered twice, when both deliveries are
      processed, then exactly one transaction exists.
- [x] **A23.** Given expenses captured by two different members, when the ledger is
      inspected, then each transaction carries the correct submitter.
- [x] **A23a.** Given a transaction captured from a text message, when its
      original message is requested, then the exact text sent is returned,
      unmodified by extraction, correction or anything said about it since; and
      given a capture that took a question and an answer to resolve, then both
      messages are returned in order, not only the first.
- [x] **A24.** Given a stated date in the past, such as "coffee 350 yesterday",
      when it is captured, then the transaction is dated correctly in the
      household's timezone.
- [x] **A25.** Given a capture at a merchant never seen before, when it is
      recorded, then it is unconfirmed; and given a capture at a known merchant
      below the threshold, when the quiet period passes with nobody touching it,
      then it becomes confirmed with the route recorded.
- [x] **A26.** Given a member whose language is Russian, when they send «кофе 350»,
      then the transaction is recorded identically to the English case and the
      reply is in Russian.
- [x] **A27.** Given a category, when it is rendered for each member, then both
      see their own language's display name for the same underlying slug.
- [x] **A28.** Given a model response that does not satisfy the declared schema,
      when it is processed, then nothing is written and the capture becomes
      unparsed.
- [x] **A29.** Given a prompt file removed from the mount, when the system starts,
      then it fails loudly and does not run with a stale or absent prompt.
- [x] **A30.** Given any write path, whether the bot, an import or a correction,
      when a transaction is written with no acting member, then the database
      rejects it.
- [x] **A31.** Given a capture naming an account the household does not have,
      when it is processed, then no account is created and the capture becomes
      unparsed with one question.
- [x] **A32.** Given a confirmation message, when a member taps approve, then the
      record is confirmed; and when they type the equivalent instead, the outcome
      is identical.
- [x] **A33.** Given a member's last action of any kind, when they say "undo",
      then it is reversed by a compensating change, the original rows remain in the
      audit log, and another member's last action is untouched.
- [x] **A34.** Given "кофе 350, подарок Маше", when captured, then the note is
      stored on the transaction and appears when that transaction is shown.
- [x] **A34a.** Given a standing fact the agent has kept via `remember`, when a
      later, unrelated capture is composed, then the reply or the extraction
      reflects it; and given an admin deletes that memory row, then a
      following capture no longer does.
- [x] **A35.** Given a previous coffee at a known merchant, when the member says
      "как обычно", then a transaction with the same amount, category and account
      is recorded dated today and unconfirmed.
- [x] **A36.** Given several recent captures, when a member asks for them, then a
      short list is returned with per-item actions.
- [x] **A37.** Given an expense charged in Swiss francs at a stated EUR amount,
      when recorded, then both the original amount with its currency and the EUR
      amount are stored.
- [x] **A38.** Given a setup conversation paused halfway, when an admin asks what
      remains, then the outstanding steps are listed and the conversation resumes
      from there.
- [x] **A39.** Given a setup conversation paused halfway, when the containers are
      restarted, then it resumes from the same step, which proves the state is in
      the database and not in an execution context.
- [x] **A40.** Given a scripted multi-turn exchange, made of a capture that
      cannot be parsed, a question, an answer that still leaves a gap, a further
      question, and a final answer that resolves it, when it is replayed as a
      test, then the transaction is recorded and the capture is closed, with
      every message in the exchange stored. Every conversational flow has such
      a test.
- [x] **A41.** Given the same pending question, when the workflow runs again
      without new information, then the question is not repeated.
- [x] **A42.** Given each declared tool, when it is called with deliberately
      malformed input, then nothing is written; and when it is called as a member
      who is not allowed to use it, then it fails at the database.
- [x] **A43.** Given unconfirmed transactions exist, when an admin asks in chat,
      then they are listed and can be confirmed in one reply.

## Edge cases and failures

The table below pairs each situation a capture can land in with what the system
does about it. Read it as the failure contract for text capture: anything not
listed here is an unparsed capture with one question.

| Situation | Expected behaviour |
|---|---|
| Amount written with a comma decimal separator, as Dutch usage has it | Interpreted correctly; 24,40 is 24.40 |
| Amount with no currency | Recorded in EUR, the household default |
| Amount in another currency | Recorded as the amount charged in EUR if stated; otherwise treated as an unparsed capture with a question |
| Two amounts in one message | One question asked instead of a guess |
| Message contains several expenses | Out of scope for this slice: treated as an unparsed capture with a question, never partially recorded |
| Merchant name that is also a category word ("Bakery") | Merchant registry consulted first; ambiguity resolved by asking |
| Member has no default payment account set | The capture is refused with a question naming the choices, and nothing is guessed |
| Expense dated before an account's opening balance | Recorded, and flagged to the admins, because it makes the opening balance wrong |
| Correction sent long after the capture | Applies to the transaction the member names; "the last one" refers only to their own most recent |
| Model returns an unbalanced or nonsensical result | Rejected by the invariant, stored as unparsed, never written half |
| Model names an account that does not exist, as in "from savings" | Unparsed capture and one question. The agent never creates an account unasked (ADR 0031), so an invented account is a refusal rather than a new row |
| Model proposes a category that nearly duplicates an existing one | Created and flagged unreviewed; merging is an admin action, not a silent match |
| Very long or nonsense message | Unparsed capture; no model cost beyond one attempt |
| A capture mixing both languages in one message | Interpreted normally; language affects the reply, not the extraction |
| An auto-confirm threshold set to zero | Nothing auto-confirms; the queue is drained only by review or matching |
| Two members capture at the same moment | Both recorded; attribution not mixed |

## Ergonomic cost

- **Who does more work:** nobody, and that is the requirement. Capture replaces
  work that is not being done at all today. An admin gains the review pass from
  R20, which is bounded by auto-confirmation and, from spec 0007, drained by
  reconciliation.
- **What queue or obligation it creates:** two queues, both bounded. Unconfirmed
  records (ADR 0023) drain by review, by matching, or by the quiet-period rule.
  Unparsed captures drain by the member answering the question asked, and a
  further one where a single answer was not enough, and they stay visible rather
  than accumulate silently.
- **What it interrupts, and how often:** one confirmation per capture, to the
  person who captured. Nothing else: no alerts, no nudges, no daily summary.
- **If nobody touches it for a month:** nothing breaks and nothing is lost.
  Unconfirmed records stay in the books and countable, and unanswered questions
  wait. The month simply has less in it, and spec 0007's import can fill it in
  later.

## Non-functional requirements

- **Latency:** a confirmation arrives within a few seconds of sending, because a
  member at a till will not wait.
- **Cost:** a capture matching a known merchant must not require a model call,
  and model spend per capture must be bounded by a single attempt.
- **Data minimisation:** the model receives the capture text only, never the ledger,
  per ADR 0029.
- **Correctness over completeness:** refusing to record is always better than a
  wrong or half-written transaction.
- **Latency and cost follow the shared baselines** in
  [docs/standards/budgets.md](../../docs/standards/budgets.md); the figures above
  refine them rather than replace them.
- **Failure states are named** from
  [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).
- **Time is typed deliberately:** a booking date is a calendar date, not a moment;
  anything that is a moment is stored as `timestamptz` in UTC and rendered in the
  household's timezone. A date must never shift because of where a server is.

## Open questions

None. We decided everything this slice needed decided; what the household must
still supply is listed in spec 0001 and spec 0002.

## Related

- ADRs: 0004, 0008, 0011, 0016, 0017, 0021, 0023, 0025, 0027, 0029, 0030, 0031, 0038, 0039, 0040, 0042, 0043, 0044
- Specs: 0001 and 0002 (must be done first), 0004, 0005, 0006, 0007
