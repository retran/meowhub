---
id: 0001
title: n8n as the automation and agent platform
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0001 - n8n as the automation and agent platform

## Context

We build meowhub low-code on purpose, as the vision says, because an admin's
time should go into scenarios and not into infrastructure. That choice puts six
demands on whatever platform we run the automation on:

- run self-hosted, on a cheap VPS now and on a home server later (ADR 0002);
- speak Telegram natively, including files, photos and voice notes;
- call an LLM with tools and hold a conversation, not just fire single prompts;
- reach PostgreSQL and run SQL;
- let workflows be exported as text and version-controlled on GitHub;
- allow narrow custom code where blocks run out.

The owner also raised a licensing worry, because he has to be able to publish
his own repository on GitHub and run the system both on rented hosting and at
home. n8n ships under the Sustainable Use License, which is source-available
and not OSI open source. Its terms permit use and modification "for your own
internal business purposes or for non-commercial or personal use", and they
restrict *distributing n8n itself* commercially. A private household
installation stays inside those terms, and so does a repository that holds only
our own workflows, because the workflows are our content and not a
redistribution of n8n.

## Decision

We use **n8n**, self-hosted, community edition, as the automation and agent
platform, and it owns all orchestration: Telegram handling, LLM calls, ledger
writes and scheduled jobs.

We export workflows as JSON into `workflows/` in this repository and review them
as code, so the repository is the source of truth and the running n8n instance
is not.

We write custom logic in Code nodes and in SQL, keep it small and keep it inside
n8n. Adding a separate service needs its own ADR.

We rely on no n8n enterprise feature. Where a need maps onto one, as single
sign-on does (ADR 0032), we solve it outside n8n instead of paying for the
edition.

## Alternatives

| Option | Why rejected |
|---|---|
| Activepieces (MIT community edition) | Genuinely OSI-licensed and self-hostable, and the closest runner-up. Its piece ecosystem is smaller and its agent and LLM tooling less mature than n8n's, and the licensing worry that motivated the comparison turned out not to apply. Kept as the documented escape hatch if n8n's terms ever change |
| Node-RED (Apache-2.0) | Solid, tiny footprint, truly open source, but it has no agent or LLM abstractions, so we would hand-roll the tool-calling loop in function nodes. That is code, which is what low-code was meant to avoid |
| Windmill (AGPLv3) | The strongest alternative: code-first in TypeScript, Python, Go and SQL with a Rust executor, two-way git sync (the one axis where n8n is weak), and its own app builder. We rejected it because n8n's advantage falls exactly where we would otherwise write the most ourselves, in Telegram media handling and an agent loop with tools. Windmill is the answer if the scheduled half - digests, statement import, restore verification - should become TypeScript instead of nodes, and running both orchestrators is not worth the cost |
| Dify / Flowise / Langflow | Strong at building agents, weak at the boring integration half: Telegram file handling, scheduling and statement imports. Each would need a second orchestrator alongside it, which doubles the moving parts |
| Make.com / Zapier | Neither can be self-hosted at all, so the portability constraint disqualifies them |
| Writing the service ourselves (the nexus approach) | We already tried it in nexus, and it costs exactly the ownership burden that meowhub exists to avoid |

## Consequences

We get three things from n8n that we would otherwise build ourselves:

- Telegram, PostgreSQL, HTTP and LLM agent nodes come out of the box, so the
  first slice is plumbing instead of construction.
- One Docker container plus PostgreSQL runs identically on the VPS and at home.
- Workflow JSON in git gives us review and rollback for changes that would
  otherwise be invisible clicks in a UI.

We accept four costs in return:

- n8n is not OSI open source. We take a source-available license for a private
  household system, with the boundary described in the context above.
- Workflow JSON diffs badly, so review leans on the spec and on testing instead
  of on reading the diff.
- We give up every enterprise-gated feature, single sign-on among them.
- Logic in a visual tool is harder to unit-test than plain code, so each plan
  has to say how it checks a workflow.

One choice gets harder to reverse later: moving off n8n means rewriting every
workflow, because no portable format exists between low-code platforms. We keep
that cost down by holding domain logic in SQL and in the database schema, where
it survives a platform change, and by keeping workflows thin.
