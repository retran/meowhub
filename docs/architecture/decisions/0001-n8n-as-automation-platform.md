---
id: 0001
title: n8n as the automation and agent platform
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0001 — n8n as the automation and agent platform

## Context

meowhub is built low-code on purpose (see the vision): an admin's time should go
into scenarios, not into infrastructure. The platform must:

- run self-hosted, on a cheap VPS now and on a home server later (ADR 0002);
- speak Telegram natively, including files, photos and voice notes;
- call an LLM with tools and hold a conversation, not just fire single prompts;
- reach PostgreSQL and run SQL;
- let workflows be exported as text and version-controlled on GitHub;
- allow narrow custom code where blocks run out.

A licensing constraint was raised and examined: an admin must be able to publish
his own repository on GitHub and run the system on rented hosting and at home.
n8n is under the Sustainable Use License, which is source-available but not OSI
open source. Its terms permit use and modification "for your own internal
business purposes or for non-commercial or personal use", and restrict
*distributing n8n itself* commercially. A private household installation and a
repository containing only our own workflows fall inside those terms; the
workflows are our content, not a redistribution of n8n.

## Decision

We use **n8n**, self-hosted, community edition, as the automation and agent
platform. It owns all orchestration: Telegram handling, LLM calls, ledger writes
and scheduled jobs.

Workflows are exported as JSON into `workflows/` in this repository and reviewed
as code. The n8n instance is not the source of truth — the repository is.

Custom logic is written in Code nodes and SQL, kept small and kept inside n8n. A
separate service is a decision that requires its own ADR.

We do not rely on any n8n enterprise feature. Where a need maps onto one (SSO
being the known case, see ADR 0032), we solve it outside n8n rather than pay for
the edition.

## Alternatives

| Option | Why rejected |
|---|---|
| Activepieces (MIT community edition) | Genuinely OSI-licensed and self-hostable, and the closest runner-up. Smaller piece ecosystem and less mature agent/LLM tooling than n8n, and the licensing worry that motivated it turned out not to apply. Kept as the documented escape hatch if n8n's terms ever change |
| Node-RED (Apache-2.0) | Solid, tiny footprint, truly open source, but has no agent or LLM abstractions — the tool-calling loop would be hand-rolled in function nodes. That is code, which is what low-code was meant to avoid |
| Windmill (AGPLv3) | The strongest alternative: code-first in TypeScript, Python, Go and SQL with a Rust executor, two-way git sync — the one axis where n8n is weak — and its own app builder. Rejected because n8n's advantage is concentrated exactly where we would otherwise write the most ourselves: Telegram media handling and an agent loop with tools. Windmill is the answer if the scheduled half — digests, statement import, restore verification — should become TypeScript rather than nodes; running both is not worth two orchestrators |
| Dify / Flowise / Langflow | Strong at agent construction, weak at the boring integration half (Telegram file handling, scheduling, statement imports). Would need a second orchestrator alongside, doubling the moving parts |
| Make.com / Zapier | No self-hosting path at all. Disqualified by the portability constraint |
| Writing the service ourselves (the nexus approach) | Already tried in nexus. It is exactly the cost of ownership meowhub exists to avoid |

## Consequences

**Good:**
- Telegram, PostgreSQL, HTTP and LLM agent nodes exist out of the box; the first
  slice is plumbing, not construction.
- One Docker container plus PostgreSQL; identical on the VPS and at home.
- Workflow JSON in git gives review and rollback for changes that would otherwise
  be invisible clicks in a UI.

**Bad, and the price we accept:**
- Not OSI open source. We accept a source-available license for a private
  household system, with the boundary above understood.
- Workflow JSON has poor diff readability; review leans on the spec and on
  testing rather than on reading the diff.
- Enterprise-gated features (SSO among them) are off the table by choice.
- Logic in a visual tool is harder to unit-test than plain code; the verification
  strategy in each plan has to say how a workflow is actually checked.

**What becomes harder to change later:**
- Migrating away means rewriting every workflow; there is no portable format
  between low-code platforms. The mitigation is keeping domain logic in SQL and
  in the database schema, where it survives a platform change, and keeping
  workflows thin.
