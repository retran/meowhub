---
id: 0030
title: A member is an account of ours; Telegram is a channel linked to it by an admin
status: accepted
date: 2026-09-12
deciders: owner
supersedes: [0005]
superseded-by: []
---

# ADR 0030 — A member is an account of ours; Telegram is a channel linked to it by an admin

## Context

Three people use the system: two parents as admins and a daughter as a member,
and **all three have accounts** — for the app, and for the bot.

Identity has to answer two different questions. Who is allowed to reach the
household's books, on any surface; and who submitted a particular capture, since
attribution can never be null (ADR 0011). Taking the Telegram user id as the
answer to both makes the messenger the root of identity, which is the deepest
coupling in the system: changing messenger would mean re-establishing who
everyone is, and a member who leaves Telegram would cease to exist rather than
cease to have a channel.

## Decision

**A member is a row in our own `members` table, with our own identifier.** That
row is the identity. Everything else is a link to it.

- **Channels are linked, not authoritative.** A Telegram user id is a *channel
  binding* on a member — one column, one table — and the same member is reachable
  by any channel we later support. Identity survives the messenger.
- **An admin links the channel.** A member's Telegram id is attached by an admin,
  never claimed by self-service. In practice: the member messages the bot, the bot
  offers a one-time code to whoever is unlinked, and an admin confirms which
  member it is. An unlinked Telegram id reaches nothing and is logged.
- **The identity provider's subject is another link on the same row**, so the app
  and the bot resolve to one member (ADR 0032). One person, one member, two
  bindings.
- **Every member has an account**, with both sign-in methods enrolled, whether or
  not they use the app much. Roles stay `admin` and `member` (ADR 0016).
- **Attribution references the member**, never a channel id, so a re-linked or
  changed Telegram account leaves history intact.
- **Deactivation is on the member** (ADR 0026): the row stays, the links are
  revoked, and every past transaction keeps its submitter.

## Alternatives

| Option | Why rejected |
|---|---|
| The Telegram user id *is* the member, keyed directly | What ADR 0005 decided. Simplest, and it makes the messenger the root of identity: no app account without a chat, no changing channel without a migration of the member table, and a person who abandons Telegram disappears rather than becoming unreachable |
| The identity provider's subject is the member | Closer, and it forces every member through a web sign-in before they can capture anything — which is exactly the friction the chat-first principle exists to avoid |
| Self-service linking: a member proves their own Telegram id | Convenient, and it turns the allow-list into an enrolment flow that someone could walk into. At three people, an admin confirming is one message |
| Allow several Telegram accounts per member | Harmless in principle, and it invites ambiguity in attribution for no benefit anyone asked for. One binding per channel per member, changeable by an admin |

## Consequences

**Good:**
- The messenger becomes replaceable: ADR 0027's escape hatch is now a new channel
  binding rather than a redefinition of who everybody is.
- One person is one member across the bot and the app, so per-member reports,
  languages and permissions are the same thing everywhere.
- A member exists before they have a channel, which makes onboarding an admin
  action rather than a race.
- Attribution is stable through account changes, which matters when history is the
  asset.

**Bad, and the price we accept:**
- One more indirection: two joins where there was one column, and an unlinked
  member is a state that has to be handled everywhere a capture arrives.
- Onboarding needs a small linking flow — a code, and an admin's confirmation —
  which is work that the previous design got for free.
- An admin can mis-link a channel to the wrong member, attributing captures to the
  wrong person until noticed. The audit log makes it visible and correctable
  (ADR 0008).

**What becomes harder to change later:** nothing. This is the change that makes
the rest easier, which is why it is worth the indirection.
