---
id: 0043
title: A member may message the bot privately or from one shared household group
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
amends: [0027]
---

# ADR 0043 - A member may message the bot privately or from one shared household group

## Context

ADR 0027 chose private one-to-one chats only, because attribution is then
unambiguous and a correction isn't a public event. That reasoning assumed a
group chat would force every member into visibility they hadn't chosen.

The household now wants a shared group chat as well as private ones, because a
household is one unit and a member can capture in front of the others or alone.
This ADR amends the single clause of ADR 0027 that said otherwise, and changes
nothing else in it: Telegram is still the platform, the bot is still the only
interface object, and the numeric user id is still the member's identity.

Attribution never needed the private-only restriction. Telegram's own
`message.from` names the sender on every message, in a group the same as in a
private chat, and the normalisation step has always read exactly that
(`channel_id: String(msg.from.id)`, never the chat). The restriction decided who
sees the reply, not who gets credited for the message.

## Decision

A member can message the bot from their own private chat, from one shared
household group, or from both, choosing freely per message. The bot replies
wherever the message came from, so a private capture gets a private reply and a
group capture gets a reply in the group, visible to whoever is in it.

A shared chat also means shared context. The agent follows a group as one
ongoing conversation, the way a person sitting in it would, instead of treating
it as several private threads that happen to render in the same window. In
detail:

- Attribution stays per member, and its structure doesn't change.
  `member_channel` is keyed on the Telegram user id and never on a chat id
  (ADR 0030), so a transaction still has exactly one submitter (R6) whether or
  not the message arrived in a group.
- `capture` records which chat a message came from, as `chat_id`, the Telegram
  chat rather than the sender. Recording it is what makes shared context
  possible: when the agent composes a reply to an ambiguous or follow-on
  message, it considers recent messages from that whole chat, across every
  member in it, and not only the sending member's own earlier messages. When one
  member types "actually I paid for that one" about a capture another member
  sent, the agent has to understand the reference, because it's reading one
  conversation the way a person in the room would.
- `conversation` stays keyed on `member_id`, because a pending question or a
  setup step resolves to one person's answer and one person's bookkeeping. That
  key still lets the workflow query `capture` by `chat_id` for context when it
  decides what to ask or how to read a reply. Per-member state and shared
  awareness answer two different questions: who a capture belongs to, and what
  the agent already knows from the room.
- Each sender chooses how private a reply is by choosing where to send the
  message, so privacy isn't a property of the deployment. A member who wants
  their captures unseen by the rest of the household uses their private chat,
  and a member happy to capture in front of everyone, with the agent following
  the whole exchange, uses the group. Both work, and we enforce neither.
- The bot's group privacy mode is disabled through BotFather's `/setprivacy`,
  so it receives every message sent in the group and not only the ones that
  `@mention` it. Leaving it on would make "coffee 350" typed in the group reach
  nobody at all, which is the worst version of this failure.
- The household has one shared group. Splitting into several group chats would
  be a different feature, with per-group scoping and per-group permissions, and
  nobody has asked for it.

## Alternatives

| Option | Why rejected |
|---|---|
| Keep ADR 0027 as written, private only | The household is asking to move past it, because a group chat is a real, wanted mode |
| Group chat only, retire private chats | Removes a mode some members still want, capturing unseen by the rest of the household, and attribution is already chat-independent, so we don't have to choose |
| A separate bot registration for the group | Two bots cost two tokens, two webhooks, and two places where idempotency and deduplication (ADR 0033) have to hold, and buy nothing, because the existing bot already receives from any chat it belongs to |
| Redact or summarise replies differently in the group, for example by hiding the amount | Solves a problem nobody described, since the household chose the group in order to see each other's captures there, and a member who wants privacy already has the private chat |
| Treat the group as several isolated per-member threads that share a window | The simpler implementation, and not what the household asked for: a shared chat means shared context, so one member correcting or continuing another's message has to work as it would for a person reading the whole conversation |

## Consequences

Good:
- Neither the schema nor attribution changed, because the design was already
  chat-independent where it mattered, so the whole change is a bot setting plus
  confirming that the reply path stays keyed on the incoming chat id, which the
  Reply step already used.
- No member is forced into one mode, so the household's own social norms decide
  who captures where instead of a deployment flag.

Bad, and the price we accept:
- We now keep two delivery surfaces working, tested, and idempotent
  (ADR 0033): the private chats and the group.
- A confirmation, a correction, or an unparsed capture's question is sometimes
  public within the household when it's sent from the group. We accept that per
  member and per message, and it isn't a leak, because the sender chose the
  chat.

Nothing structural becomes harder to change later. Adding a second shared group,
if anyone ever asks, would need real design covering which group a member's
message belongs to and what each group's settings are, and this ADR deliberately
doesn't build toward it.
