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

# ADR 0033 - Telegram updates arrive by webhook when deployed and by long polling locally

## Context

ADR 0027 chose Telegram and said updates arrive by webhook into n8n, which is
right for a deployed system and impossible on a laptop, because a webhook needs a
public HTTPS endpoint and a developer's machine has none. With only that path,
the only way to exercise the capture contour - the most important behaviour in
the product - is to deploy first, which turns the feedback loop into a
deployment.

Telegram offers both directions: `setWebhook` pushes updates, and `getUpdates`
long polling pulls them. A bot can use only one of them at a time.

This ADR amends one clause of ADR 0027, that updates arrive by webhook.
Everything else in it stands.

## Decision

We support both modes and choose between them by configuration, and the transport
stays confined to one normalisation step (ADR 0027) so nothing downstream knows
which mode is running.

Deployed environments use the webhook, because it costs less, delivers
immediately, and is what the relay already terminates (ADR 0002). Local
development uses long polling, so a developer needs no tunnel, no domain, and no
inbound path: the workflow asks Telegram for updates. One environment variable
selects the mode, so switching is not a code change.

Locally we use a second bot token, because only one delivery mode can be active
per bot and a developer polling with the production token would silently take the
household's messages. The local bot is a separate registration, and its token
lives in the shared vault like any other.

Idempotency has to hold in both modes (spec 0003), because polling re-delivers an
update after a crash between fetch and acknowledgement, exactly as webhooks
retry. Tests use neither mode: workflow tests feed a fixture update directly (ADR
0015), so the suite needs no bot and no network, and polling is there for a person
trying something by hand.

## Alternatives

| Option | Why rejected |
|---|---|
| Webhook only, as ADR 0027 said | Makes the deployed system the only place the capture contour can be exercised, so every experiment is a deploy |
| A tunnel to the laptop for local webhooks | Works - and it needs a tunnel per developer, a public hostname, and it puts a third party in the loop for a five-minute experiment |
| Polling everywhere, including production | One path instead of two, at the cost of a constant poll loop, added latency on every capture, and a worse failure mode when the loop dies quietly |
| Share one bot between local and deployed | Impossible in practice: one delivery mode per bot means whoever polls takes the messages. This is the trap the separate local token exists to avoid |
| Only fixture-driven tests, no local bot at all | The suite is already fixture-driven, and it cannot tell you how a real voice note from a real phone behaves. That is what polling is for |

## Consequences

Good:
- A developer can exercise the capture contour on a laptop against the seeded
  household, with no tunnel and no deployment.
- The choice is configuration, so no local-only code path sits around rotting.
- Production keeps the cheaper, lower-latency mode.

Bad, and the price we accept:
- We support two delivery paths, and the trigger behaves slightly differently
  between them, which is the kind of difference that hides a bug until it appears
  in one environment only.
- We manage a second bot registration and token, including in the vault (ADR
  0024).
- Someone will eventually run a local poller against the production token and
  wonder where the household's messages went. The separate token is the
  mitigation, and the documentation has to say so plainly.

Nothing becomes harder to change later, because both modes are Telegram's own
mechanisms sitting behind one normalisation step.
