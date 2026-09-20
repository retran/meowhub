---
id: 0028
title: EU data residency is the direction, with the data stores there from the start
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0028 - EU data residency is the direction, with the data stores there from the start

## Context

The household lives and banks in the Netherlands and wants its financial records
processed and stored in the European Union, which covers hosting as much as
anything else.

The owner treats that as a direction rather than a gate, because he'd rather
start now and tighten later than wait for a system where every hop is provably
EU-resident. A US-incorporated provider running an EU region is acceptable, since
the requirement is about where the data sits and gets processed rather than about
a company's registered address.

Without a decision, that nuance decays in one of two ways: every component choice
reopens a residency argument, or someone adopts a convenient US service and
nobody records what left. This ADR prevents both, and it's the only place that
lists the current gaps.

## Decision

We sort every component into one of three tiers, deliberately, and this section
gives the tiers and the rules that keep the sorting honest.

### Tier 1 - the data stores are in the EU from the start, and stay there

Tier 1 is non-negotiable, because these components hold the asset and because EU
options cost the same as any other:

| What | Where |
|---|---|
| PostgreSQL: the ledger, the audit log, the forecast tables | The household's own host - Hetzner (DE/FI), then its own hardware (ADR 0002) |
| Receipt and statement files | The same host's volume (ADR 0019) |
| Offsite backups | EU object storage - a Hetzner Storage Box, or Scaleway or OVHcloud (ADR 0009), encrypted client-side regardless |
| Every self-hosted component's state | The same host |

The books never leave the EU. That part of the decision has no exceptions and no
trajectory: it holds on day one.

### Tier 2 - an EU region at a non-EU company is acceptable

A provider that runs EU infrastructure and processes there satisfies this
decision, and we note a US parent company without treating it as a
disqualification. Tier 2 is what keeps the system practical, and it covers
ingress (ADR 0002) and any managed piece we adopt later.

### Tier 3 - accepted gaps, listed here and nowhere else

Every gap below sits in the capture and access paths, and none of them goes near
the books:

| Gap | What actually crosses | Why accepted | What closes it |
|---|---|---|---|
| Telegram (ADR 0027) | Capture text, receipt photos, voice notes, and who captured when. Telegram says EEA personal data sits in Netherlands data centres and has an EU Article 27 representative, but publishes no processing agreement, no subprocessor list and no standard contractual clauses, and bot chats are not end-to-end encrypted - so it is claimed rather than verifiable | The messengers with verifiable residency are ones nobody in the household uses, and an interface nobody opens collects nothing | A self-hosted Matrix homeserver, if adoption ever stops being the binding constraint |
| The model gateway (ADR 0029) | One capture per call - text, an image or an audio clip. Never the ledger | Model quality is the product's accuracy, and the best multimodal models are not EU-resident. Starting with them is the deliberate trade | The ladder in ADR 0029: EU provider allowlist with fallbacks disabled, then an EU-region provider endpoint, then local models on the home server |
| Sign in with Apple (ADR 0032) | Authentication metadata: who signed in, when. No financial data | Passkeys, which are EU-clean, stay enrolled for every member and are sufficient alone | Switching the Apple source off, which changes nothing else |

### The rules that keep this honest

Three rules stop the tiers becoming a story we tell ourselves.

We place a new component in a tier when we adopt it, in its own ADR, in one
sentence; a component that would put household data outside the EU belongs in
tier 1's list or nowhere. Tier 3 stays a closed list, so adding to it means
naming a closing step, which is what stops "not strict" turning into "not
considered". Each gap carries that closing step, so tightening is a task rather
than an ambition, and we revisit the residency direction when the home server
arrives, because two of the three steps become cheap there.

## Alternatives

| Option | Why rejected |
|---|---|
| A hard gate: nothing adopted unless every hop is EU-resident | The owner's own answer is that this is not strict and the household would rather start. It would also cost the product its best extraction quality and its only viable messenger |
| Leave it as a preference, unwritten | Decays into drift. Six months on, nobody can say what left the EU without re-reading every decision |
| Require EU-incorporated companies, not merely EU regions | Stronger against compulsory access, and it eliminates most competent options for no benefit the household values |
| Defer the whole question until the home server exists | Half the gaps close there, and the data stores - the part that matters most - are trivially EU from day one. There is no reason to wait for the easy part |

## Consequences

Good:
- The part that matters is settled immediately, because the books, the files, and
  the backups are in the EU on day one at no cost in convenience.
- One table lists the gaps with their closing steps, so tightening is a backlog
  rather than a debate.
- Component choices stay practical, because an EU region is enough and the best
  tool is usually still available.
- Nothing blocks the first slices.

Bad, and the price we accept:
- Captures, including photographs of receipts, cross the border twice, through
  Telegram and through the model gateway. We accept that ongoing exposure of
  daily life in exchange for adoption and accuracy.
- A direction needs the discipline a gate would have enforced, because the tier-3
  list stays short only if we place every new component.
- Two of the three closing steps depend on hardware the household doesn't own
  yet, so they're intentions waiting on someone else's shopping.

Nothing technical becomes harder to change later. What this makes hard is silent
drift: the list is the mechanism, so an unlisted gap is a defect.
