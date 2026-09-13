---
id: 0003
title: OpenRouter as the single model gateway
status: superseded
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: [0029]
---

# ADR 0003 — OpenRouter as the single model gateway

> **Superseded by [ADR 0029](./0029-model-gateway-and-per-task-routing.md)**, which
> adds an explicit model-per-task routing table, hard spend caps, and a residency
> ladder. The reasoning below stands as written; the successor carries the current
> decision.

## Context

The agent needs language models for parsing expenses out of free text, reading
receipt photos, and answering questions about the ledger. These are different
jobs with different cost and capability profiles, and the best model for each
changes every few months.

Running models locally on the home server was considered. It is attractive for
privacy, but local vision and reasoning quality at household-server scale is not
yet good enough for receipt extraction, and it would make the first slice depend
on hardware the household does not have.

## Decision

All model calls go through **OpenRouter** as a single gateway, with one API key
and one HTTP contract. Model choice per use case is configuration, not code.

Constraints on how we use it:

- **Model ids live in environment configuration**, never hard-coded in workflow
  JSON. Switching a model is a config change and a restart.
- **Model choice per job, deliberately cheap by default.** A small fast model for
  parsing plain text; a multimodal Gemini Flash model for receipt photos *and*
  voice notes, which it handles natively — the owner has had this working well on
  an earlier Flash generation, and it removes the need for a separate speech-to-text
  service entirely. Report answering gets whatever is currently strongest at SQL
  reasoning. Each choice is recorded in the slice's plan, not here, because it
  changes faster than this ADR should.
- **One dependency to verify before relying on it:** audio input must actually
  pass through OpenRouter to the chosen model. If it does not, the fallbacks in
  order are calling the model's own API directly for that one call, or adding a
  transcription step. This is the multimodal slice's first task, not an
  assumption.
- **Every call is treated as fallible**: timeouts, retries and a recorded failure
  state. An unavailable model degrades a capture to an "unparsed capture"
  (see the glossary), never to a lost message.
- **Prompts and their expected output schema live in the repository**, not only
  inside n8n, so they are reviewable and diffable.
- **Spend is capped at the gateway, not only watched.** The account is funded with
  prepaid credits and the key carries a spend limit, so a runaway loop — a PDF
  retried in circles — costs a bounded amount rather than an unbounded one. Cost
  per call is recorded in the audit log (ADR 0008), and a daily threshold alerts
  the admins in Telegram (ADR 0020). Choosing *which* model is deliberately left to
  configuration and to testing, which is the point of using a gateway at all;
  choosing *how much it may spend* is not left open.
- **Only the data needed for the task is sent.** Parsing a capture sends that
  capture, not the ledger. Report questions send aggregates, not raw history.

## Alternatives

| Option | Why rejected |
|---|---|
| A single provider's API directly (Anthropic, OpenAI, Google) | Locks model choice to one vendor's catalogue and one billing relationship, for no gain — the gateway speaks the same shape |
| Local models on the home server (Ollama, llama.cpp) | The privacy-optimal answer, and the intended direction eventually. Not viable now: receipt vision quality and the absence of the hardware would both block the first slice. Revisit as its own ADR when the home server exists |
| A self-hosted gateway in front of providers (LiteLLM) | Adds a container and a failure mode to solve routing we would then configure by hand. Reconsider if OpenRouter itself becomes the problem |

## Consequences

**Good:**
- One key, one contract, one bill; swapping models is configuration.
- Cheap models for cheap jobs, strong models for receipt reading, decided per
  use case and changed without touching workflows.
- A single multimodal model covers photo and voice, so there is no
  speech-to-text service to run, pay for or self-host.
- New models become available without any change to workflows.

**Bad, and the price we accept:**
- This is the one accepted exception to "everything self-hosted": expense text
  and receipt images leave the household. The data minimisation rules above are
  the mitigation, and the household knows the trade.
- OpenRouter is a single point of failure and an extra hop of latency in front of
  the providers.
- Usage-based cost is the only non-fixed cost in the system, so prompt size and
  call frequency are a budget concern, not just a performance one.

**What becomes harder to change later:**
- Little. The gateway is one HTTP node and a key; moving to local models or to a
  provider directly means changing the call, not the ledger or the workflows'
  shape. Keeping prompts in the repository is what preserves that freedom.
