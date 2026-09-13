---
id: 0010
title: Every tool's configuration is exported, committed and restorable from this repository
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amended-by: [0031, 0034]
---

# ADR 0010 — Every tool's configuration is exported, committed and restorable from this repository

## Context

Low-code means configuration *is* the system. A workflow built by clicking, a
dashboard bound to a query, an identity provider's flow — if those live only
inside running containers, then the repository documents a system that does not
exist, reviews are impossible, and ADR 0009's backups are the only copy of the
project's actual logic.

The honest state of the tools we chose is mixed, and the decision has to account
for that rather than assume uniform support:

| Tool | Config as code? | Mechanism |
|---|---|---|
| Docker Compose | Yes, natively | The Compose file and `.env.example` are the source |
| PostgreSQL schema | Yes, natively | Versioned SQL migration files (ADR 0004) |
| Authentik | Yes, natively | Blueprints: declarative YAML applied at startup |
| n8n | Partly | Workflows and credentials export as JSON via the CLI. **Native git sync is an enterprise feature**, which ADR 0001 rules out — so export is scripted, not built in |
| Household app | Yes, natively | It *is* code in this repository — Next.js and Tailwind, edited by the agent or by the owner through Onlook (ADR 0007). The builder-export problem disappeared with the builder |
| PostgREST | Yes | Almost no configuration of its own: the views and the row-level security policies are the configuration, and both are migrations |
| Cloudflare Tunnel | Yes | Tunnel configuration is YAML; the token is a secret, not config |
| restic backups | Yes | Scripts and environment, no UI state |

So: n8n is the soft spot, and it is the tool where the conversational logic
lives.

## Decision

**The repository is the source of truth for configuration; the running system is
a deployment of it.** Everything needed to rebuild meowhub from an empty host,
apart from secrets and data, is committed here.

- **Scripted export, on a schedule and before every change is considered done.**
  A task exports n8n workflows and writes them into the repository. Because n8n community has no git sync, this is a cron job plus a
  manual `task export` — and a spec is not `done` until the export is committed.
- **Authentik is configured only through blueprints**, never by clicking. A
  change made in the UI is treated as drift to be reverted or promoted into a
  blueprint.
- **Schema changes are migrations only.** No ad-hoc DDL on a live database, even
  for a one-column fix.
- **Secrets are never in the repository.** `.env.example` documents every
  variable by name; values live in each admin's password manager (ADR 0009).
- **Drift is detected, not hoped away.** A scheduled job exports and compares
  against the committed copy, and reports a difference to the admins in Telegram.
  For n8n, drift is the normal failure mode — someone fixes a live
  workflow at 23:00 — so detection matters more than discipline.
- **The bar is a rebuild, not a backup:** a fresh host plus this repository plus
  the secrets plus a database restore must produce a working system. That claim
  is tested in the home-server migration slice.

n8n is now the only soft spot: its workflow JSON is the one artefact whose diff
is technically readable and practically not.

## Alternatives

| Option | Why rejected |
|---|---|
| n8n enterprise source control | Solves the soft spot properly, and contradicts ADR 0001's commitment to the community edition. A scripted export is the cost of that choice |
| Terraform or Pulumi over the whole stack | Real value at fleet scale; for one Compose file and one host it adds a toolchain and a state file to manage for no gain |
| Ansible for host provisioning | Reasonable, and may still arrive with the home-server slice. Not needed while the host is one VPS created once |
| Accept the UI as the source of truth, rely on backups | Then the repository lies, changes cannot be reviewed, and rebuilding means restoring a whole machine image. It also makes this project's spec-driven process meaningless |
| Only export on demand, by hand | Guarantees drift. The one thing we know about manual export steps is that they are skipped |

## Consequences

**Good:**
- A change to a workflow is reviewable in a pull request, not invisible.
- Rebuilding on new hardware is a checkout plus a restore.
- The spec-driven process has something concrete to review for low-code changes.

**Bad, and the price we accept:**
- Export and drift detection are custom plumbing we maintain, because the
  community edition does not provide it.
- Workflow JSON and app bundles produce diffs that are technically readable and
  practically not. Review leans on the spec and on testing.
- An extra step before a change is done, which will feel like friction exactly
  when someone is in a hurry.

**What becomes harder to change later:**
- Nothing. This decision makes every other tool easier to replace, because what
  it does is written down.
