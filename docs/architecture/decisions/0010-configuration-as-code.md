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

# ADR 0010 - Every tool's configuration is exported, committed and restorable from this repository

## Context

In a low-code system the configuration *is* the system: a workflow built by
clicking, a dashboard bound to a query, an identity provider's flow. If those
live only inside running containers, the repository describes a system that does
not exist, nobody can review a change, and ADR 0009's backups hold the only copy
of the project's actual logic.

The tools we chose support this unevenly, and the decision has to work with what
each one gives us:

| Tool | Config as code? | Mechanism |
|---|---|---|
| Docker Compose | Yes, natively | The Compose file and `.env.example` are the source |
| PostgreSQL schema | Yes, natively | Versioned SQL migration files (ADR 0004) |
| Authentik | Yes, natively | Blueprints: declarative YAML applied at startup |
| n8n | Partly | Workflows and credentials export as JSON through the CLI. Native git sync is an enterprise feature, which ADR 0001 rules out, so we script the export instead |
| Household app | Yes, natively | It *is* code in this repository, Next.js and Tailwind, edited by the agent or by the owner through Onlook (ADR 0007). Dropping the builder dropped the builder-export problem with it |
| PostgREST | Yes | It has almost no configuration of its own: the views and the row-level security policies are the configuration, and both are migrations |
| Cloudflare Tunnel | Yes | Tunnel configuration is YAML, and the token is a secret rather than config |
| restic backups | Yes | Scripts and environment, with no UI state |

The table leaves one soft spot, n8n, and that is the tool where the
conversational logic lives.

## Decision

**The repository is the source of truth for configuration, and the running
system is a deployment of it.** Everything needed to rebuild meowhub from an
empty host is committed here, apart from secrets and data. Six rules follow:

- We export on a schedule and again before we call a change done. A task exports
  n8n workflows and writes them into the repository. Because n8n community has
  no git sync, that is a cron job plus a manual `task export`, and a spec is not
  `done` until the export is committed.
- We configure Authentik only through blueprints and never by clicking, and we
  treat a change made in the UI as drift to revert or to promote into a
  blueprint.
- We change the schema only through migrations, with no ad-hoc DDL on a live
  database, even for a one-column fix.
- We keep secrets out of the repository. `.env.example` documents every variable
  by name, and the values live in each admin's password manager (ADR 0009).
- We detect drift instead of hoping it away: a scheduled job exports, compares
  against the committed copy, and reports a difference to the admins in
  Telegram. For n8n, drift is the normal failure mode, because somebody fixes a
  live workflow at 23:00, so detecting it matters more than discipline does.
- We hold ourselves to a rebuild and not a backup: a fresh host, this
  repository, the secrets and a database restore have to produce a working
  system. The home-server migration slice tests that claim.

Workflow JSON remains the one artefact whose diff is technically readable and
practically not.

## Alternatives

| Option | Why rejected |
|---|---|
| n8n enterprise source control | Solves the soft spot properly, and contradicts ADR 0001's commitment to the community edition. A scripted export is what that choice costs us |
| Terraform or Pulumi over the whole stack | Worth real money at fleet scale. For one Compose file and one host it adds a toolchain and a state file to manage and returns nothing |
| Ansible for host provisioning | Reasonable, and it might still arrive with the home-server slice. We don't need it while the host is one VPS created once |
| Accept the UI as the source of truth, rely on backups | Then the repository lies, nobody can review a change, and rebuilding means restoring a whole machine image. It would also make this project's spec-driven process meaningless |
| Only export on demand, by hand | Guarantees drift, because the one thing we know about manual export steps is that people skip them |

## Consequences

We gain three things:

- A change to a workflow becomes reviewable in a pull request instead of
  invisible.
- Rebuilding on new hardware is a checkout plus a restore.
- The spec-driven process gets something concrete to review for a low-code
  change.

We accept three costs in return:

- We maintain the export and drift detection ourselves, because the community
  edition gives us neither.
- Workflow JSON and app bundles diff badly, so review leans on the spec and on
  testing.
- Every change carries one more step before it is done, and that step will feel
  like friction exactly when somebody is in a hurry.

Nothing gets harder to change later. This decision makes every other tool easier
to replace, because what each one does is written down.
