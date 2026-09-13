---
id: 0033
title: Telegram updates arrive by webhook when deployed and by long polling locally
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amends: [0027]
---

# ADR 0033 — Telegram updates arrive by webhook when deployed and by long polling locally

## Context

ADR 0027 chose Telegram and said updates arrive by webhook into n8n. That is
right for a deployed system and impossible on a laptop: a webhook needs a public
HTTPS endpoint, and a developer's machine has none. Without a second path, the
only way to exercise the capture contour — the most important behaviour in the
product — is to deploy first, which makes the feedback loop a deployment.

Telegram offers both: `setWebhook` for push, and `getUpdates` long polling for
pull. They are mutually exclusive per bot at any moment.

This amends one clause of ADR 0027 — that updates arrive by webhook. Everything
else in it stands.

## Decision

**Both modes, chosen by configuration**, with the transport still confined to one
normalisation step (ADR 0027) so nothing downstream knows which is in use.

- **Deployed environments use the webhook.** It is cheaper, immediate, and it is
  what the relay already terminates (ADR 0002).
- **Local development uses long polling.** No tunnel, no domain, no inbound path:
  the workflow asks Telegram for updates.
- **The mode is one environment variable**, and switching it is not a code change.
- **A second bot token is used locally.** Only one delivery mode can be active per
  bot, so a developer polling with the production token would silently steal the
  household's messages. The local bot is a separate registration, and its token is
  in the shared vault like any other.
- **Idempotency must hold in both modes** (spec 0003): polling re-delivers on a
  crash between fetch and acknowledgement, exactly as webhooks retry.
- **Tests use neither.** Workflow tests feed a fixture update directly
  (ADR 0015), so the suite needs no bot and no network at all. Polling is for a
  person trying something by hand.

## Alternatives

| Option | Why rejected |
|---|---|
| Webhook only, as ADR 0027 said | Makes the deployed system the only place the capture contour can be exercised, so every experiment is a deploy |
| A tunnel to the laptop for local webhooks | Works — and it needs a tunnel per developer, a public hostname, and it puts a third party in the loop for a five-minute experiment |
| Polling everywhere, including production | One path instead of two, at the cost of a constant poll loop, added latency on every capture, and a worse failure mode when the loop dies quietly |
| Share one bot between local and deployed | Impossible in practice: one delivery mode per bot means whoever polls takes the messages. This is the trap the separate local token exists to avoid |
| Only fixture-driven tests, no local bot at all | The suite is already fixture-driven, and it cannot tell you how a real voice note from a real phone behaves. That is what polling is for |

## Consequences

**Good:**
- The capture contour can be exercised on a laptop, against the seeded household,
  with no tunnel and no deployment.
- The choice is configuration, so there is no local-only code path to rot.
- Production keeps the cheaper, lower-latency mode.

**Bad, and the price we accept:**
- Two delivery paths to support, and the trigger's behaviour differs slightly
  between them — the kind of difference that hides a bug until it appears in only
  one environment.
- A second bot registration and token to manage, including in the vault
  (ADR 0024).
- Someone will eventually run a local poller against the production token and
  wonder why the household's messages vanished. The separate token is the
  mitigation; the documentation has to say it plainly.

**What becomes harder to change later:** nothing. Both are Telegram's own
mechanisms behind one normalisation step.
