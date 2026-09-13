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

# ADR 0027 — Telegram is the conversational platform, and the source of member identity

## Context

Chat is the primary interface (vision principle 1), so the messenger is not a
detail of the implementation — it decides whether the product is used at all. It
also supplies member identity (ADR 0030), which makes it the deepest coupling in
the system.

What the product needs from it:

- **A real bot API**, with webhooks that reach a self-hosted service — because
  every workflow depends on it (ADR 0001).
- **Files, photos and voice notes** delivered in a form we can download and store
  (ADRs 0013, 0019).
- **A stable per-person identifier**, since attribution cannot be null (ADR 0011).
- **Already installed on every household device.** An interface nobody has open
  receives no captures, and this household is entirely on Apple hardware.
- **No per-message cost and no approval process**, because a household cannot
  live inside a commercial messaging quota.

## Decision

**Telegram.** Private chats between each member and one registered bot; webhooks
into n8n; the Telegram numeric user id is the member's identity (ADR 0030).

- **Private chats, not a group.** Attribution is unambiguous and a correction is
  not a public event.
- **The bot is the only interface object.** No channels, no inline bots, no
  mini-apps: the household app is a separate surface behind its own boundary
  (ADRs 0007, 0014).
- **The transport is confined to one place.** Workflows receive an already
  normalised message — sender, text, attachments, language — so the rest of the
  system never touches Telegram's shapes. That is what keeps a future change of
  messenger from being a rewrite.

## Alternatives

| Option | Why rejected |
|---|---|
| **iMessage** | The household's native messenger, on every device they own, and the obvious first thought. Rejected on fact rather than taste: Apple provides **no third-party bot API**. Automating it means an always-on Mac driving the Messages app through unofficial tooling — fragile, outside the terms of service, and it would tie the household's bookkeeping to a machine in the living room staying awake |
| **WhatsApp** | Ubiquitous, and its Business API needs a Meta business account, template approval for outbound messages, a provider, and per-conversation pricing. Automating a personal account is against its terms. A bookkeeping bot does not belong inside a commercial messaging funnel |
| **Signal** | Privacy-optimal and the closest thing to a principled answer. There is no bot concept: automation means `signal-cli` impersonating a real client bound to a phone number, which breaks on protocol changes and has no stable identity model for our purposes |
| **Matrix, self-hosted** | The ideologically consistent choice — open, federated, self-hostable, and it would remove the one third party from the capture path entirely. Rejected because nobody in the household uses it. An interface that must first be installed and learned collects nothing, and adoption is the product's real risk (see `ergonomics.md`) |
| **Email** | Universally available and terrible for a one-line capture at a till |
| **A custom app with push notifications** | Full control, and it puts a build-and-install step between a person and writing "coffee 350". Contradicts the vision's chat-first principle |
| **SMS** | Costs money per message, no attachments worth the name |

## Consequences

**Good:**
- Nothing to install: capture works on the first day, on every device the
  household already carries.
- Files, photos and voice notes arrive natively, which is what makes multimodal
  capture a slice rather than a project.
- Identity is free and stable, so there is no account system for the bot.
- Free, with no quota, no approval, and no commercial relationship.

**Bad, and the price we accept:**
- **Telegram sees the capture path.** Bot conversations are not end-to-end
  encrypted: the text of every expense message, every receipt photo and every
  voice note passes through Telegram's servers, along with the metadata of who
  messages the bot and when. This is a second deliberate exception to
  self-hosting, alongside the model gateway (ADR 0029), and it is recorded in the
  threat model rather than left implicit. What never leaves is the ledger itself.
- **Identity and transport are the same dependency** (ADR 0030). Changing
  messenger later would mean re-establishing who everyone is, which is the
  expensive half — the normalisation boundary above limits the damage but does
  not remove it.
- A closed platform whose API we do not control can change under us.
- A member who stops using Telegram stops being able to capture.

**What becomes harder to change later:** the identity coupling. Confining the
transport to one normalisation step is the mitigation; the member table keying on
a Telegram id is the part that would need a migration.
