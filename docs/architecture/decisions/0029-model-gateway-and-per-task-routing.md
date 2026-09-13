---
id: 0029
title: OpenRouter with a model per task, spend capped, and a residency ladder
status: accepted
date: 2026-09-12
deciders: owner
supersedes: [0003]
superseded-by: []
---

# ADR 0029 — OpenRouter with a model per task, spend capped, and a residency ladder

## Context

The agent needs models for five distinct jobs, and treating them as one job is
how all five end up mediocre:

| Job | What it actually needs |
|---|---|
| Extract an expense from free text | Cheap, fast, bilingual, reliable structured output |
| Map a question onto a known query | Cheap, fast, strict enumeration — no creativity wanted |
| Read a receipt photo | Vision that survives crumpled thermal paper in bad light |
| Understand a voice note | Native audio, accented speech, two languages |
| Read a statement PDF | Vision plus long context plus a strict schema |

They differ by an order of magnitude in cost, and the best model for each changes
every few months.

Two further constraints, both from the household. **Spend must be bounded**: this
is the only usage-based cost in the system, and a retry loop on a PDF would be
discovered on a bill. And **EU residency is the direction** (ADR 0028) —
a direction, explicitly not a gate, because the best multimodal models are not
EU-resident and extraction quality is the product's accuracy.

## Decision

**OpenRouter remains the single gateway**, and the decision is what sits on top
of it: an explicit routing table, hard spend caps, and a residency ladder with
named rungs.

### A model per task

The routing table is the artefact expected to change most often, and it is
configuration in this repository (ADR 0010) — never hard-coded in workflow JSON:

| Task | Tier | Starting choice | If unavailable |
|---|---|---|---|
| Capture extraction, text | Small, fast | A small fast model, bilingual | Retry once, then unparsed capture |
| Question → query mapping | Small, fast | The same model | The same |
| Receipt photo | Multimodal | The strongest current multimodal model — Gemini Flash class, which the owner has had working well | A second multimodal model |
| Voice note | Multimodal, native audio | The same multimodal model; no separate speech-to-text service | Unparsed capture and a question |
| Statement PDF | Multimodal, long context | The same class, with the strict schema from ADR 0013 | Refuse the import rather than guess |
| Digests and report prose | None | No model: SQL and templates | — |

Rules that outlive any particular model:

- **Model ids are configuration.** Changing which model reads receipts is one
  line and a restart, and the choice is settled by testing (ADR 0015's golden
  set), not by this document.
- **Each task's prompt and output schema are separate** (ADR 0025). A response
  that fails its schema is an unparsed capture, never a partial write.
- **The model is never asked for a number that SQL can produce.** It maps and
  extracts; the books compute.
- **Every call is fallible**: one retry, then the unparsed path. A failure never
  loses a message.
- **Cost, latency, model and prompt version are recorded per call** (ADR 0008),
  because a routing decision without cost data is a guess.

### Spend is capped, not merely watched

- Prepaid credits, and a **spend limit on the key**, so the worst case is bounded
  rather than unbounded.
- A **per-day threshold alert** to the admins (ADR 0020).
- A capture at a known merchant costs nothing at all: the merchant registry
  answers without a model call (ADR 0004), so cost falls as the registry fills.

### The residency ladder

Residency is a direction, so it is expressed as rungs with triggers rather than
as a gate:

1. **Now: default routing, best models.** Extraction quality wins. One capture
   per call crosses the border; the ledger never does. This is the accepted gap in
   ADR 0028's tier 3.
2. **When quality allows: pin inference to the EU.** OpenRouter's own controls do
   this on a standard account — `provider.only` as an allowlist of EU-resident
   providers (Mistral in France, Scaleway, OVHcloud, IONOS, Nebius), `zdr: true`
   for zero-retention endpoints, `data_collection: "deny"`, and
   **`allow_fallbacks: false` so an unavailable provider produces an error rather
   than a quiet hop elsewhere**. Trigger: the golden set shows an EU model within
   tolerable distance of the incumbent on receipts and voice.
3. **If the gateway hop itself must be EU**: an enterprise account on
   `eu.openrouter.ai`, which decrypts and processes in the EU, or a self-hosted
   LiteLLM gateway calling EU providers directly. Trigger: the household decides
   the hop matters more than the contract or the container.
4. **Endgame: local models on the home server.** A local route in the same table,
   and the gap closes entirely. Trigger: hardware.

Each rung is a configuration change. None of them touches a prompt, a schema, a
workflow or the ledger — which is the whole reason to keep a gateway rather than
call a provider directly.

## Alternatives

| Option | Why rejected |
|---|---|
| One model for every task | Fewer moving parts, and it either overpays for text extraction or under-reads receipts. The five jobs are genuinely different |
| EU-only routing from day one | The strongest residency answer, and it starts the product at materially worse extraction — more unparsed captures, more corrections, in the slice that decides whether the household adopts it at all. Kept as rung 2, with a quality trigger rather than a date |
| Enterprise EU endpoint now | Closes the hop properly, at enterprise contract terms for a three-person household |
| Self-hosted LiteLLM gateway now | Removes the intermediary and keeps per-task routing — and trades a managed gateway for a container we operate, two commercial relationships, and our own budget plumbing, to protect a hop that carries one capture. Kept as rung 3 |
| Provider APIs directly, no gateway | Hard-codes a provider into every workflow, loses per-task routing in one place, and makes every rung of the ladder a code change |
| A separate speech-to-text service for voice | An extra dependency to run and pay for, when a multimodal model reads audio natively |
| No spend cap, just alerts | An alert tells you after the money is gone. The cap is the control; the alert is the notice |

## Consequences

**Good:**
- Each job gets a model suited to it, and the choice is a line of configuration
  settled by measurement.
- The product starts with the best available extraction, which is what adoption
  depends on.
- Spend has a ceiling, and falls as the merchant registry grows.
- Residency has a written path with triggers, so tightening is a task rather than
  an argument — and every rung is configuration.

**Bad, and the price we accept:**
- **Captures cross the border today.** One capture per call — text, a receipt
  photograph, or a voice clip — reaches a non-EU provider. Accepted deliberately
  in ADR 0028, and closed by rung 2 or 4.
- A routing table is one more thing to keep current; a stale table quietly pays
  for yesterday's model.
- Per-task routing means five prompts and five schemas to maintain rather than
  one.
- The gateway is a single point of failure in front of every provider, and an
  extra hop of latency.

**What becomes harder to change later:** nothing much. Prompts and schemas are
provider-agnostic by design (ADR 0025), and the routing table is data — which is
what makes all four rungs of the ladder cheap.
