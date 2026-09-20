---
id: 0030
title: A member is an account of ours; Telegram is a channel linked to it by an admin
status: accepted
date: 2026-09-12
deciders: owner
supersedes: [0005]
superseded-by: []
---

# ADR 0030 - A member is an account of ours; Telegram is a channel linked to it by an admin

## Context

Three people use the system - two parents as admins and a daughter as a member -
and all three have accounts, for the app and for the bot.

Identity has to answer two different questions: who can reach the household's
books on any surface, and who submitted a particular capture, since attribution
can never be null (ADR 0011). Answering both with the Telegram user id makes the
messenger the root of identity, which is the deepest coupling we could build.
Changing messenger would then mean re-establishing who everyone is, and a member
who leaves Telegram would stop existing instead of merely losing a channel.

## Decision

A member is a row in our own `members` table, with our own identifier, and that
row is the identity. Everything else links to it.

We link channels instead of trusting them. A Telegram user id is a channel
binding on a member - one column, one table - so the same member stays reachable
through any channel we support later and the identity outlives the messenger.

An admin creates that link, and a member never claims it by self-service. In
practice the member messages the bot, the bot offers a one-time code to whoever
is unlinked, and an admin confirms which member it belongs to. An unlinked
Telegram id reaches nothing, and we log the attempt.

The identity provider's subject is another link on the same row, so the app and
the bot resolve to one member (ADR 0032): one person, one member, two bindings.
Every member has an account with both sign-in methods enrolled, whether or not
they use the app much, and the roles stay `admin` and `member` (ADR 0016).

Attribution references the member and never a channel id, so re-linking or
changing a Telegram account leaves history intact. Deactivation also happens on
the member (ADR 0026): the row stays, we revoke the links, and every past
transaction keeps its submitter.

## Alternatives

| Option | Why rejected |
|---|---|
| The Telegram user id is the member, keyed directly | What ADR 0005 decided. Simplest, and it makes the messenger the root of identity: no app account without a chat, no changing channel without a migration of the member table, and a person who abandons Telegram disappears rather than becoming unreachable |
| The identity provider's subject is the member | Closer, and it forces every member through a web sign-in before they can capture anything - which is exactly the friction the chat-first principle exists to avoid |
| Self-service linking: a member proves their own Telegram id | Convenient, and it turns the allow-list into an enrolment flow that someone could walk into. At three people, an admin confirming is one message |
| Allow several Telegram accounts per member | Harmless in principle, and it invites ambiguity in attribution for no benefit anyone asked for. One binding per channel per member, changeable by an admin |

## Consequences

Good:
- The messenger becomes replaceable, because ADR 0027's escape hatch is now a new
  channel binding instead of a redefinition of who everybody is.
- One person is one member across the bot and the app, so per-member reports,
  languages, and permissions mean the same thing everywhere.
- A member exists before they have a channel, which makes onboarding an admin
  action instead of a race.
- Attribution survives account changes, which matters when history is the asset.

Bad, and the price we accept:
- We add one indirection: two joins where there was one column, and every place a
  capture arrives has to handle an unlinked member.
- Onboarding needs a small linking flow - a code and an admin's confirmation -
  which the previous design got for free.
- An admin can link a channel to the wrong member and attribute captures to the
  wrong person until someone notices. The audit log makes that visible and
  correctable (ADR 0008).

Nothing becomes harder to change later. This is the change that makes the rest
easier, which is why the indirection is worth paying for.
