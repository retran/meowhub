---
id: 0005
title: Household membership via a Telegram allow-list
status: superseded
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: [0030]
---

# ADR 0005 — Household membership via a Telegram allow-list

> **Superseded by [ADR 0030](./0030-identity-is-ours-telegram-is-a-linked-channel.md).**
> A member is now an account of ours with Telegram linked to it by an admin,
> rather than a row keyed by a Telegram id. The reasoning below stands as written;
> the successor carries the current decision.

## Context

Three people use the bot: two parents and a daughter. They share one ledger, and
every entry has to record who submitted it. The bot is reachable by anyone who
finds it on Telegram, so it needs to reject strangers — a public bot with an open
household ledger behind it is not acceptable.

There is no requirement for accounts, passwords or sign-up: the household is a
fixed, tiny, known set of people.

## Decision

Telegram is the conversational platform (ADR 0027); this decides who may use it.

A member is a row in the `members` table keyed by **Telegram user id**. Messages
from any id not in that table are refused with a neutral reply and logged; they
never reach the agent or the ledger.

- Membership is managed by an admin, through a bot command or a direct database
  row — not by self-service sign-up.
- The Telegram user id is the identity; the display name is cached for
  convenience only, because Telegram usernames change.
- Every ledger entry carries the submitting member. Attribution is not optional
  and cannot be null.
- All members see the whole shared ledger. Who may *change* what is recorded is
  decided in ADR 0016: admins only, with category and project attribution
  exempted as classification (ADR 0021).
- **A member's role is either `admin` or `member`, and admin is deliberately held
  by two people** — both parents. The daughter is a `member`. Only an `admin`
  manages membership, edits recorded transactions (ADR 0016) and runs destructive
  operations such as an import reversal.
- **No capability in this system belongs to one individual.** Two admins is the
  household's answer to a single point of human failure, and it is why secret
  custody (ADR 0024) is held by both rather than by one.

This ADR covers the household's use of the bot. Access to the administrative
interfaces (n8n itself, dashboards) is a different problem, decided in ADR 0032.

## Alternatives

| Option | Why rejected |
|---|---|
| Shared Telegram group, one chat for everyone | Attribution would rest on who happened to send the message in a busy chat, and private corrections would be public. Private chats per member are cleaner and Telegram gives the identity for free |
| A real identity system (accounts, passwords, OIDC) for bot users | Enormous overhead for three known people who already have Telegram identities |
| No allow-list, just don't publish the bot name | Bot tokens and usernames leak; an open ledger is too high a price for saving one table |
| Per-member private ledgers | Contradicts the product goal: the point is one household picture |

## Consequences

**Good:**
- Access control is one table and one check at the top of every workflow.
- Attribution comes free from the Telegram message.
- No passwords, no sign-up flow, nothing to reset.

**Bad, and the price we accept:**
- Onboarding a person is a manual act by an admin. At three members, that is
  correct.
- Identity is only as strong as their Telegram account; if a device is
  compromised, the ledger is readable. Accepted for household bookkeeping.
- Telegram is a hard dependency for identity as well as for transport, which
  makes replacing the interface later more than a transport change.

**What becomes harder to change later:**
- Adding per-member visibility rules after everyone is used to seeing everything
  would be a product change, not just a technical one. The schema keeps the door
  open by recording attribution on every transaction from the start.
