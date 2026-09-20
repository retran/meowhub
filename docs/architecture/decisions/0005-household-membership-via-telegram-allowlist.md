---
id: 0005
title: Household membership via a Telegram allow-list
status: superseded
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: [0030]
---

# ADR 0005 - Household membership via a Telegram allow-list

> **Superseded by [ADR 0030](./0030-identity-is-ours-telegram-is-a-linked-channel.md).**
> A member is now an account of ours, with Telegram linked to it by an admin,
> instead of a row keyed by a Telegram id. The reasoning below stands as
> written, and the successor carries the current decision.

## Context

Three people use the bot: two parents and a daughter. They share one ledger, and
every entry has to record who submitted it. Anyone who finds the bot on Telegram
can message it, so the bot has to turn strangers away, because a public bot with
an open household ledger behind it is not acceptable.

The household needs no accounts, passwords or sign-up, since it is a fixed, tiny
and known set of people.

## Decision

Telegram is the conversational platform (ADR 0027), and this ADR decides who can
use it.

A member is a row in the `members` table keyed by Telegram user id. The bot
refuses a message from any id outside that table with a neutral reply and logs
it, and such a message never reaches the agent or the ledger. Six rules follow
from that:

- An admin manages membership, through a bot command or a direct database row,
  and nobody signs themselves up.
- The Telegram user id is the identity, and we cache the display name only for
  convenience, because Telegram usernames change.
- Every ledger entry carries the member who submitted it, in a column that
  cannot be null.
- All members see the whole shared ledger. ADR 0016 decides who can *change*
  what is recorded: admins only, except for category and project attribution,
  which counts as classifying rather than editing (ADR 0021).
- A member's role is either `admin` or `member`, and both parents hold admin
  while the daughter is a `member`. Only an `admin` manages membership, edits
  recorded transactions (ADR 0016) and runs destructive operations such as
  reversing an import.
- **Two people hold every power in this system.** Two admins are the household's
  answer to a single point of human failure, and the same reasoning puts secret
  custody (ADR 0024) in both parents' hands.

This ADR covers how the household uses the bot. ADR 0032 decides who reaches the
administrative interfaces, n8n itself and the dashboards, which is a different
problem.

## Alternatives

| Option | Why rejected |
|---|---|
| Shared Telegram group, one chat for everyone | Attribution would rest on who happened to send the message in a busy chat, and private corrections would be public. Private chats per member are cleaner, and Telegram gives us the identity for free |
| A real identity system (accounts, passwords, OIDC) for bot users | Enormous overhead for three known people who already have Telegram identities |
| No allow-list, and not publishing the bot name | Bot tokens and usernames leak, and an open ledger is too high a price for saving one table |
| Per-member private ledgers | Contradicts the product goal, which is one household picture |

## Consequences

We gain three things:

- Access control is one table and one check at the top of every workflow.
- The Telegram message tells us who submitted the entry, at no extra cost.
- No passwords, no sign-up flow and nothing to reset.

We accept three costs in return:

- An admin has to onboard each person by hand, which is the right answer at
  three members.
- An identity is only as strong as the member's Telegram account, so a
  compromised device makes the ledger readable. We accept that for household
  bookkeeping.
- Telegram becomes a hard dependency for identity as well as for transport, so
  replacing the interface later means more than changing transport.

Per-member visibility rules are what get harder to add later, because once
everyone is used to seeing everything, restricting it is a product change and
not only a technical one. The schema keeps the door open by recording who
submitted every transaction from the start.
