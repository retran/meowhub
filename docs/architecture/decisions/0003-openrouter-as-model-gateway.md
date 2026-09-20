---
id: 0003
title: OpenRouter as the single model gateway
status: superseded
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: [0029]
---

# ADR 0003 - OpenRouter as the single model gateway

> **Superseded by [ADR 0029](./0029-model-gateway-and-per-task-routing.md)**,
> which adds a routing table of one model per task, hard spend caps, and a
> residency ladder. The reasoning below stands as written, and the successor
> carries the current decision.

## Context

The agent needs language models for three jobs: parsing expenses out of free
text, reading receipt photos, and answering questions about the ledger. The
three differ in what they cost and what they demand of a model, and the best
model for each changes every few months.

We considered running models locally on the home server. Local models are
attractive for privacy, but vision and reasoning quality at household-server
scale is not yet good enough for pulling data out of a receipt, and the first
slice would then depend on hardware the household does not own.

## Decision

All model calls go through **OpenRouter** as a single gateway, with one API key
and one HTTP contract, so which model serves which use case is configuration
and not code.

We constrain how we use the gateway in seven ways:

- Model ids live in environment configuration and never in workflow JSON, so
  switching a model is a config change and a restart.
- We pick a model per job and stay cheap by default: a small fast model for
  parsing plain text, and a multimodal Gemini Flash model for receipt photos
  *and* voice notes, which it handles natively. The owner has had this working
  well on an earlier Flash generation, and it removes the need for a separate
  speech-to-text service. Report answering gets whatever is currently strongest
  at SQL reasoning. Each choice is recorded in the slice's plan rather than
  here, because it changes faster than this ADR should.
- One dependency has to be checked before we rely on it: audio input must
  actually pass through OpenRouter to the chosen model. If it does not, we call
  the model's own API directly for that one call, or we add a transcription
  step. This is the multimodal slice's first task, not an assumption.
- Every call can fail, so each one carries timeouts, retries and a recorded
  failure state. When a model is unavailable, a capture becomes an "unparsed
  capture" (see the glossary) and never a lost message.
- Prompts and the output schema each one expects live in the repository and not
  only inside n8n, so we can review and diff them.
- We cap spend at the gateway instead of only watching it. The account is funded
  with prepaid credits and the key carries a spend limit, so a runaway loop -
  a PDF retried in circles - costs a bounded amount. Cost per call goes into the
  audit log (ADR 0008), and a daily threshold alerts the admins in Telegram
  (ADR 0020). We deliberately leave *which* model to configuration and to
  testing, since that is the point of a gateway, and we leave *how much it can
  spend* fixed.
- We send only the data a task needs. Parsing a capture sends that capture and
  not the ledger, and report questions send aggregates and not raw history.

## Alternatives

| Option | Why rejected |
|---|---|
| A single provider's API directly (Anthropic, OpenAI, Google) | Locks model choice to one vendor's catalogue and one billing relationship and gains nothing, because the gateway speaks the same shape |
| Local models on the home server (Ollama, llama.cpp) | The best answer for privacy, and where we want to end up. Not viable now: receipt vision quality and the missing hardware would each block the first slice. We revisit it in its own ADR once the home server exists |
| A self-hosted gateway in front of providers (LiteLLM) | Adds a container and a failure mode to solve routing that we would then configure by hand. We reconsider it if OpenRouter itself becomes the problem |

## Consequences

We gain four things:

- One key, one contract and one bill, so swapping models is configuration.
- Cheap models for cheap jobs and strong models for reading receipts, decided
  per use case and changed without touching workflows.
- One multimodal model covers photo and voice, so we run, pay for and host no
  speech-to-text service.
- New models become available without any change to workflows.

We accept three costs in return:

- This is the one accepted exception to running everything ourselves: expense
  text and receipt images leave the household. We limit what we send, as the
  decision above says, and the household knows the trade.
- OpenRouter is a single point of failure and one more hop of latency in front
  of the providers.
- Usage-based cost is the only non-fixed cost in the system, so prompt size and
  how often we call are a budget question as well as a performance one.

Little gets harder to reverse. The gateway is one HTTP node and a key, so moving
to local models or to a provider directly changes the call and leaves the ledger
and the workflows alone. Keeping prompts in the repository is what preserves
that freedom.
