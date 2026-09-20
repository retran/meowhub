---
id: 0029
title: OpenRouter with a model per task, spend capped, and a residency ladder
status: accepted
date: 2026-09-12
deciders: owner
supersedes: [0003]
superseded-by: []
amended-by: [0046]
---

# ADR 0029 - OpenRouter with a model per task, spend capped, and a residency ladder

## Context

The agent needs models for five distinct jobs, and if we treat them as one job
all five come out mediocre:

| Job | What it actually needs |
|---|---|
| Extract an expense from free text | Cheap, fast, bilingual, reliable structured output |
| Map a question onto a known query | Cheap, fast, strict enumeration - no creativity wanted |
| Read a receipt photo | Vision that survives crumpled thermal paper in bad light |
| Understand a voice note | Native audio, accented speech, two languages |
| Read a statement PDF | Vision plus long context plus a strict schema |

The five jobs differ by a factor of ten in cost, and the best model for each one
changes every few months.

The household adds two more constraints. Spend has to stay bounded, because model
calls are the only usage-based cost in the system and a retry loop on a PDF would
first show up on a bill. EU residency is the direction (ADR 0028), and explicitly
not a gate, because the best multimodal models aren't EU-resident and extraction
quality is the product's accuracy.

## Decision

OpenRouter stays the single gateway, and we put three things on top of it: an
explicit routing table, hard spend caps, and a residency ladder with named rungs.

### A model per task

We expect the routing table to change more often than anything else here, so we
keep it as configuration in this repository (ADR 0010) and never hard-code it in
workflow JSON:

| Task | Tier | Starting choice | If unavailable |
|---|---|---|---|
| Capture extraction, text | Small, fast | A small fast model, bilingual | Retry once, then unparsed capture |
| Question to query mapping | Small, fast | The same model | The same |
| Receipt photo | Multimodal | The strongest current multimodal model - Gemini Flash class, which the owner has had working well | A second multimodal model |
| Voice note | Multimodal, native audio | The same multimodal model; no separate speech-to-text service | Unparsed capture and a question |
| Statement PDF | Multimodal, long context | The same class, with the strict schema from ADR 0013 | Refuse the import rather than guess |
| Digests and report prose | None | No model: SQL and templates | - |

The rules below outlive any particular model in that table.

Model ids are configuration, so changing which model reads receipts takes one
line and a restart, and the golden set settles the choice by measurement (ADR
0015). Each task keeps its own prompt and output schema (ADR
0025), and a response that fails its schema becomes an unparsed capture instead
of a partial write. We never ask a model for a number SQL can produce: the model
maps and extracts, and the books compute. We treat every call as fallible, with
one retry and then the unparsed path, so a failure never loses a message. And we
record cost, latency, model, and prompt version per call (ADR 0008), because a
routing decision without cost data is a guess.

### Spend is capped, not merely watched

We buy prepaid credits and set a spend limit on the key, which caps the worst
case at the credits we bought, and a per-day threshold alert reaches the admins
(ADR 0020). A capture at a known merchant costs nothing at all, because the
merchant registry answers without a model call (ADR 0004), so cost falls as the
registry fills.

### The residency ladder

Because residency is a direction, we write it as rungs, each with the trigger
that moves us up to it:

1. Now, we use default routing and the best models, because extraction quality
   wins. One capture per call crosses the border and the ledger never does, which
   is the accepted gap in ADR 0028's tier 3.
2. When quality allows, we pin inference to the EU. OpenRouter's own controls do
   this on a standard account: `provider.only` as an allowlist of EU-resident
   providers (Mistral in France, Scaleway, OVHcloud, IONOS, Nebius), `zdr: true`
   for zero-retention endpoints, `data_collection: "deny"`, and
   `allow_fallbacks: false` so an unavailable provider raises an error instead of
   hopping quietly elsewhere. The trigger is the golden set showing an EU model
   within tolerable distance of the incumbent on receipts and voice.
3. If the gateway hop itself has to be EU, we move to an enterprise account on
   `eu.openrouter.ai`, which decrypts and processes in the EU, or to a
   self-hosted LiteLLM gateway calling EU providers directly. The trigger is the
   household deciding the hop matters more than the contract or the container.
4. In the endgame we run local models on the home server, as another route in the
   same table, and the gap closes entirely. The trigger is hardware.

Each rung is a configuration change, and none of them touches a prompt, a schema,
a workflow, or the ledger. The gateway is what buys that, because it holds every
provider choice in one table.

## Alternatives

| Option | Why rejected |
|---|---|
| One model for every task | Fewer moving parts, and it either overpays for text extraction or under-reads receipts. The five jobs are genuinely different |
| EU-only routing from day one | The strongest residency answer, and it starts the product at materially worse extraction - more unparsed captures, more corrections, in the slice that decides whether the household adopts it at all. Kept as rung 2, with a quality trigger rather than a date |
| Enterprise EU endpoint now | Closes the hop properly, at enterprise contract terms for a three-person household |
| Self-hosted LiteLLM gateway now | Removes the intermediary and keeps per-task routing - and trades a managed gateway for a container we operate, two commercial relationships, and our own budget plumbing, to protect a hop that carries one capture. Kept as rung 3 |
| Provider APIs directly, no gateway | Hard-codes a provider into every workflow, loses per-task routing in one place, and makes every rung of the ladder a code change |
| A separate speech-to-text service for voice | An extra dependency to run and pay for, when a multimodal model reads audio natively |
| No spend cap, just alerts | An alert tells you after the money is gone. The cap is the control; the alert is the notice |

## Consequences

Good:
- Each job gets a model suited to it, and the choice is a line of configuration
  that measurement settles.
- The product starts with the best available extraction, which is what adoption
  depends on.
- Spend has a ceiling, and it falls as the merchant registry grows.
- Residency has a written path with triggers, and every rung is configuration, so
  tightening it is a scheduled task once its trigger fires.

Bad, and the price we accept:
- Captures cross the border today: one capture per call - text, a receipt
  photograph, or a voice clip - reaches a non-EU provider. We accepted that
  deliberately in ADR 0028, and rung 2 or rung 4 closes it.
- The routing table is one more thing to keep current, and a stale table quietly
  pays for yesterday's model.
- Per-task routing leaves us five prompts and five schemas to keep current, five
  times the upkeep a single prompt would cost.
- The gateway stands in front of every provider, so it's a single point of
  failure and an extra hop of latency.

Changing any of this later stays cheap, because prompts and schemas are
provider-agnostic by design (ADR 0025) and the routing table is data. That is
what makes all four rungs of the ladder affordable.
