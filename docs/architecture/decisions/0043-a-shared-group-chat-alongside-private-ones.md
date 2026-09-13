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

# ADR 0043 — A member may message the bot privately or from one shared household group

## Context

ADR 0027 chose private 1:1 chats only, for a stated reason: attribution is
unambiguous and a correction is not a public event. That reasoning assumed a
group chat would force every member into visibility they had not chosen.

The household now wants a shared group chat as well as private ones — a
household is one unit, and a member is free to capture in front of the others or
alone. This amends the one clause of ADR 0027 that said otherwise; nothing else
in that decision changes: Telegram is still the platform, the bot is still the
only interface object, and the numeric user id is still the member's identity.

Nothing about attribution actually required the private-only restriction in the
first place. Telegram's own `message.from` names the sender on every message,
in a group exactly as in a private chat — a fact the normalisation step already
reads and always has (`channel_id: String(msg.from.id)`, never the chat). The
restriction was about who *sees the reply*, not who is credited for the message.

## Decision

**A member may message the bot from their own private chat, from one shared
household group, or both — freely, per message.** The bot replies in whichever
the message came from: a private capture gets a private reply, a group capture
gets a reply in the group, visible to whoever is in it.

**A shared chat means shared context, not merely shared visibility.** A group
is one ongoing conversation the agent follows, the way a person sitting in it
would — not several members' private threads that happen to render in the same
window. Concretely:

- **Attribution stays per-member and is unaffected structurally.**
  `member_channel` is keyed on the Telegram user id, never on a chat id
  (ADR 0030) — a transaction still has exactly one submitter (R6), and that
  does not change because the message arrived in a group.
- **`capture` records which chat a message came from** (`chat_id`, the
  Telegram chat, distinct from the sender). This is what makes shared context
  possible: composing a reply to an ambiguous or follow-on message considers
  recent messages **from that whole chat**, across every member in it, not
  only the sending member's own prior messages. "actually I paid for that
  one" from a different member than who sent the original capture must be
  understood as referring to it — the agent is reading one conversation, the
  same as a person in the room would.
- **`conversation` stays keyed on `member_id`**, because a pending question or
  a setup step still resolves to one specific person's answer and one
  specific person's bookkeeping — but nothing about that key stops the
  workflow querying `capture` by `chat_id` for situational context when
  composing what to ask or how to interpret a reply. Per-member state and
  shared awareness are not the same axis, and this is deliberately both: who
  a capture belongs to is one question, what the agent already knows from the
  room is another.
- **A reply's privacy is the sender's own choice, made by where they send the
  message** — not a property of the deployment. A member who wants their
  captures unseen by the rest of the household uses their private chat; a
  member happy to capture in front of everyone, with the agent following the
  whole exchange, uses the group. Both work, and neither is enforced.
- **The bot's group privacy mode is disabled** (BotFather's `/setprivacy`),
  so it receives every message sent in the group, not only ones that
  `@mention` it — otherwise "coffee 350" typed in the group would silently
  reach nobody, the worst version of this failure.
- **One shared group**, not several. Nothing here supports the household
  splitting into multiple group chats; that is a materially different feature
  (per-group scoping, per-group permissions) that nobody has asked for.

## Alternatives

| Option | Why rejected |
|---|---|
| Keep ADR 0027 as written, private only | What the household is now asking to move past — a group chat is a real, wanted mode, not a hypothetical |
| Group chat only, retire private chats | Removes a mode some members may still want (capturing unseen by the rest of the household); nothing requires choosing one over the other once attribution is already chat-independent |
| A separate bot registration for the group | Two bots means two tokens, two webhooks, and two places idempotency and dedup (ADR 0033) have to hold independently for no benefit — the existing bot already receives from any chat it is a member of |
| Redact or summarise replies differently in the group (e.g. hide the amount) | Solves a problem nobody described; the household chose the group precisely to see each other's captures there. A member wanting privacy already has the private-chat option |
| Treat the group as N isolated per-member threads that happen to share a window | The simpler implementation, and it is not what was asked for: a shared chat means shared context — one member correcting or continuing another's message must work, the way it would if a person were reading the whole conversation |

## Consequences

**Good:**
- No schema or attribution change was needed — the design was already
  chat-independent where it mattered, so this is a genuinely small change: a bot
  setting and confirming the reply path stays keyed on the incoming chat id
  (which the "Reply" step already used).
- A member is not forced into one mode; the household's own social norms decide
  who captures where, not a deployment flag.

**Bad, and the price we accept:**
- Two live delivery surfaces (private chats, the group) to keep working
  correctly, tested, and idempotent (ADR 0033) rather than one.
- A confirmation, a correction, or an unparsed capture's question is now
  sometimes genuinely public within the household when sent from the group —
  accepted deliberately, per member, per message; not a leak, since it was the
  sender's own choice of chat.

**What becomes harder to change later:** nothing structural. Adding a second
shared group, if ever asked for, would need real design (which group a
member's message belongs to, per-group settings); this ADR deliberately does
not build toward that.
