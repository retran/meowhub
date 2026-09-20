---
id: 0027
title: Telegram is the conversational platform, and the source of member identity
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amended-by: [0030, 0033, 0043]
---

# ADR 0027 - Telegram is the conversational platform, and the source of member identity

## Context

Chat is the primary interface (vision principle 1), so the messenger decides
whether the household uses the product at all rather than being an implementation
detail. It also supplies member identity (ADR 0030), which makes it the deepest
coupling in the system.

We need five things from a messenger. It has to offer a real bot API with
webhooks that reach a self-hosted service, because every workflow depends on that
(ADR 0001). It has to deliver files, photos, and voice notes in a form we can
download and store (ADRs 0013, 0019). It has to give each person a stable
identifier, because attribution can't be null (ADR 0011). It has to be installed
already on every household device - this household is entirely on Apple hardware,
and an interface nobody has open receives no captures. And it has to cost nothing
per message and need no approval, because a household can't live inside a
commercial messaging quota.

## Decision

We use Telegram: private chats between each member and one registered bot,
webhooks into n8n, and the Telegram numeric user id as the member's identity (ADR
0030).

Each member talks to the bot in a private chat rather than a group, so
attribution is unambiguous and a correction isn't a public event. The bot is the
only interface object we use - no channels, no inline bots, no mini-apps -
because the household app is a separate surface behind its own boundary (ADRs
0007, 0014).

We confine the transport to one place. Workflows receive an already normalised
message - sender, text, attachments, language - so the rest of the system never
touches Telegram's shapes, which is what keeps a later change of messenger from
becoming a rewrite.

## Alternatives

| Option | Why rejected |
|---|---|
| iMessage | The household's native messenger, on every device they own, and the obvious first thought. Rejected on fact rather than taste: Apple provides no third-party bot API. Automating it means an always-on Mac driving the Messages app through unofficial tooling - fragile, outside the terms of service, and it would tie the household's bookkeeping to a machine in the living room staying awake |
| WhatsApp | Ubiquitous, and its Business API needs a Meta business account, template approval for outbound messages, a provider, and per-conversation pricing. Automating a personal account is against its terms. A bookkeeping bot does not belong inside a commercial messaging funnel |
| Signal | Privacy-optimal and the closest thing to a principled answer. Signal has no bot concept: automation means `signal-cli` impersonating a real client bound to a phone number, which breaks on protocol changes and has no stable identity model for our purposes |
| Matrix, self-hosted | The ideologically consistent choice - open, federated, self-hostable, and it would remove the one third party from the capture path entirely. Rejected because nobody in the household uses it. An interface that must first be installed and learned collects nothing, and adoption is the product's real risk (see `ergonomics.md`) |
| Email | Universally available and terrible for a one-line capture at a till |
| A custom app with push notifications | Full control, and it puts a build-and-install step between a person and writing "coffee 350". Contradicts the vision's chat-first principle |
| SMS | Costs money per message, no attachments worth the name |

## Consequences

Good:
- Nobody installs anything, so capture works on the first day, on every device
  the household already carries.
- Files, photos, and voice notes arrive natively, which is what makes multimodal
  capture a slice rather than a project.
- Identity comes free and stays stable, so the bot needs no account system.
- Telegram costs nothing and imposes no quota, no approval, and no commercial
  relationship.

Bad, and the price we accept:
- Telegram sees the capture path, because bot conversations aren't end-to-end
  encrypted: the text of every expense message, every receipt photo, and every
  voice note passes through Telegram's servers, along with the metadata of who
  messages the bot and when. We accept this as the second deliberate exception to
  self-hosting, alongside the model gateway (ADR 0029), and we record it in the
  threat model instead of leaving it implicit. The ledger itself never leaves.
- Identity and transport are the same dependency (ADR 0030), so changing
  messenger later would mean re-establishing who everyone is, which is the
  expensive half. The normalisation boundary above limits that damage without
  removing it.
- Telegram is a closed platform whose API we don't control, so it can change
  under us.
- A member who stops using Telegram stops being able to capture.

What becomes harder to change later is the identity coupling. Confining the
transport to one normalisation step is our mitigation, and the member table
keying on a Telegram id is the part that would need a migration.
