---
id: 0028
title: EU data residency is the direction, with the data stores there from the start
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0028 — EU data residency is the direction, with the data stores there from the start

## Context

The household lives and banks in the Netherlands, and wants its financial
records processed and stored in the European Union. That preference covers
hosting as much as anything else.

It is a **direction, not a gate**: the household would rather start and tighten
than wait for a system where every hop is provably EU-resident. And a US-
incorporated provider operating an EU region is acceptable — the requirement is
about where the data sits and is processed, not about a company's registered
address.

Without a decision, that nuance decays in one of two ways: either into paralysis,
where every component choice reopens a residency argument, or into drift, where a
convenient US service is adopted and nobody records what left. This ADR exists to
prevent both, and it is the only place the current gaps are listed.

## Decision

**Three tiers, and each component is placed in one deliberately.**

### Tier 1 — the data stores are in the EU from the start, and stay there

Non-negotiable, because these hold the asset and because EU options are as good
and as cheap as any:

| What | Where |
|---|---|
| PostgreSQL: the ledger, the audit log, the forecast tables | The household's own host — Hetzner (DE/FI), then its own hardware (ADR 0002) |
| Receipt and statement files | The same host's volume (ADR 0019) |
| Offsite backups | EU object storage — a Hetzner Storage Box, or Scaleway or OVHcloud (ADR 0009), encrypted client-side regardless |
| Every self-hosted component's state | The same host |

**The books never leave the EU.** That is the part of this decision with no
exceptions and no trajectory: it is true on day one.

### Tier 2 — an EU region at a non-EU company is acceptable

Where a provider operates EU infrastructure and processes there, that satisfies
this decision. A US parent company is a factor to note, not a disqualification.
This is what keeps the system practical, and it covers ingress (ADR 0002) and any
future managed piece.

### Tier 3 — accepted gaps, listed here and nowhere else

These are in the **capture and access paths**, never near the books:

| Gap | What actually crosses | Why accepted | What closes it |
|---|---|---|---|
| **Telegram** (ADR 0027) | Capture text, receipt photos, voice notes, and who captured when. Telegram says EEA personal data sits in Netherlands data centres and has an EU Article 27 representative, but publishes no processing agreement, no subprocessor list and no standard contractual clauses, and bot chats are not end-to-end encrypted — so it is claimed rather than verifiable | The messengers with verifiable residency are ones nobody in the household uses, and an interface nobody opens collects nothing | A self-hosted Matrix homeserver, if adoption ever stops being the binding constraint |
| **The model gateway** (ADR 0029) | One capture per call — text, an image or an audio clip. Never the ledger | Model quality is the product's accuracy, and the best multimodal models are not EU-resident. Starting with them is the deliberate trade | The ladder in ADR 0029: EU provider allowlist with fallbacks disabled, then an EU-region provider endpoint, then local models on the home server |
| **Sign in with Apple** (ADR 0032) | Authentication metadata: who signed in, when. No financial data | Passkeys, which are EU-clean, stay enrolled for every member and are sufficient alone | Switching the Apple source off, which changes nothing else |

### The rules that keep this honest

- **A new component is placed in a tier when it is adopted**, in its own ADR, in
  one sentence. A component that would put household *data* outside the EU
  belongs in tier 1's list or nowhere.
- **Tier 3 is a closed list.** Adding to it is a decision with a named closing
  step, not a shrug — which is what stops "not strict" from becoming "not
  considered".
- **Each gap carries its closing step**, so tightening is a task rather than an
  ambition. The residency direction is revisited when the home server arrives,
  which is where two of the three steps become cheap.

## Alternatives

| Option | Why rejected |
|---|---|
| A hard gate: nothing adopted unless every hop is EU-resident | The owner's own answer is that this is not strict and the household would rather start. It would also cost the product its best extraction quality and its only viable messenger |
| Leave it as a preference, unwritten | Decays into drift. Six months on, nobody can say what left the EU without re-reading every decision |
| Require EU-incorporated companies, not merely EU regions | Stronger against compulsory access, and it eliminates most competent options for no benefit the household values |
| Defer the whole question until the home server exists | Half the gaps close there, and the data stores — the part that matters most — are trivially EU from day one. There is no reason to wait for the easy part |

## Consequences

**Good:**
- The part that matters is settled immediately: the books, the files and the
  backups are in the EU on day one, at no cost in convenience.
- The gaps are enumerated in one table with their closing steps, so tightening is
  a backlog rather than a debate.
- Component choices stay practical: an EU region is enough, so the best tool is
  usually still available.
- Nothing blocks the first slices.

**Bad, and the price we accept:**
- Captures — including photographs of receipts — cross the border twice, through
  Telegram and through the model gateway. That is a real, ongoing exposure of
  daily life, accepted for adoption and accuracy.
- "Direction" requires discipline that a gate would have enforced: the tier-3
  list only stays short if every new component is actually placed.
- Two of the three closing steps depend on hardware the household does not yet
  own, so they are intentions with a date attached to someone else's shopping.

**What becomes harder to change later:** nothing technical. What this makes hard
is silent drift — the list is the mechanism, and an unlisted gap is a defect.
