---
id: 0001
title: Infrastructure bootstrap
status: done
created: 2026-09-12
updated: 2026-09-12
owner: owner
supersedes: []
---

# 0001 - Infrastructure bootstrap

## Problem

We can't verify anything in this project yet, because the household has no host,
no database, no place to run a workflow, and no way to restore what a workflow
produces. Unless one slice builds all of that first, every later slice carries
its own setup, and the first real mistake - a dropped table, a bad
reconciliation - costs the data, because the backups were still scheduled for
"later".

The second problem is how low-code systems usually get built. If you assemble
one by clicking through admin screens, nothing is left to review and nothing is
left to rebuild from, so we need the export and migration habits in place before
the first workflow exists.

## Why

After this slice the household has a running, reachable, authenticated, and
restorable installation with an empty ledger schema. We measure that by
rebuilding rather than by uptime: a fresh host, this repository, the secrets,
and the latest backup must produce the same system, because an installation
nobody can reproduce is one disk failure away from gone.

## Users and scenarios

- **Owner** wants a deployed environment so that he can build and test the next
  slice against something real.
- **Owner** wants to open the automation editor from his phone or laptop with
  Face ID, so that administering the system doesn't depend on a shared password.
- **Owner** wants to know a backup is good without being asked to check, so that
  trust in the system doesn't rest on his memory.

## Requirements

- **R1.** The whole system must be defined in one Docker Compose file, with
  every setting supplied through environment variables and no value baked into
  an image.
- **R2.** The system must run unchanged on a rented host and on a household
  machine. Only the environment variables, the DNS records, and the ingress can
  differ between the two.
- **R3.** A database must exist for household data, separate from the databases
  the platform's own components use.
- **R4.** Only versioned migration files stored in this repository must create
  or change the household data schema. They apply in order, and the system
  records which ones it has applied.
- **R5.** The Telegram bot must be reachable over HTTPS from the internet, and
  whatever provides that reach must be replaceable without changing anything
  inside the system.
- **R5a.** The public surfaces must be rate-limited at the edge. Anyone who
  finds the bot can reach the webhook, and although spec 0002 refuses an
  unlinked sender before any model is called, an unbounded flood still costs
  workflow executions and log volume.
- **R6.** Every web surface must pass through the authentication boundary before
  it is publicly reachable. This slice installs and wires that boundary; spec
  0002 decides who can sign in and what they can reach.
- **R7.** A dedicated volume must exist for uploaded files, addressed by content
  hash, and the backup set must include it.
- **R8.** Every scheduled job must report success by pushing a heartbeat, and a
  missing heartbeat inside its window must raise an alert, so that a job which
  stopped running can't look like a job that succeeded.
- **R9.** Secrets must never be stored in this repository. Every required
  variable must be documented by name with no value.
- **R9c.** Every deployment setting must be an environment variable listed in
  `.env.example`, and no component must carry a default for a required variable
  in code: a missing one must fail at startup, not at first use (ADR 0034). A
  household setting belongs in the database instead, not in `.env`.
- **R9a.** The secret inventory must be listed entry by entry, and every entry
  must have two custodians (ADR 0024). It holds at least: the restic repository
  password; the offsite storage credentials; the PostgreSQL superuser and
  per-role passwords; the Telegram bot token; the model gateway key; the
  identity provider's bootstrap and recovery credentials; the Apple `.p8`
  signing key; the PostgREST JWT secret; and the n8n encryption key, which is
  the one people forget and can't recreate, because without it every credential
  stored inside n8n is lost even though the database restores cleanly.
- **R9b.** A restore must be shown to work using only the inventory in R9a,
  which is what proves nothing undocumented is holding the system together.
- **R10.** A backup must be taken automatically every night, encrypted before it
  leaves the host, and stored both locally and in an offsite location.
- **R11.** A restore of the most recent backup must be verified automatically on
  a schedule, and the result must be reported to the admins in Telegram,
  including when the restore fails.
- **R12.** One documented command must export the configuration of every
  component that is configured through a UI into files in this repository.
- **R13.** Drift between the running configuration and the committed
  configuration must be detected on a schedule and reported to the admins.
- **R14.** Either admin must be able to run the documented rebuild procedure
  from this repository, the secrets, and a backup, with no undocumented step.
- **R14a.** The whole system must run locally as one command, with no public
  endpoint, no domain, and no tunnel: the same Compose file, a local environment
  file, and the seeded household.
- **R14b.** Telegram updates must be deliverable by webhook when deployed and by
  long polling locally, selected by one environment variable (ADR 0033), with a
  separate bot registration and token for local use.
- **R14c.** Local mode must require no paid account of any kind: the model
  gateway is stubbed (R17) and sign-in uses email and password (ADR 0032), so a
  developer needs nothing bought to exercise the system.
- **R14e.** A scaffold command must create the first admin account from
  environment variables, an email and an initial password, so that a fresh
  deployment, local or rented, can be reached without a manual step in a
  provider's UI. The command must refuse to run if any account already exists,
  and the initial password must be changed on first sign-in (spec 0002).
- **R15.** A test harness must exist and run as one command: a throwaway
  PostgreSQL with the migrations applied, a database test framework, and a seed
  script that builds the synthetic household.
- **R16.** The tests must run automatically on every push, and a failure must be
  visible without anyone looking for it. Continuous integration runs on GitHub
  Actions.
- **R16a.** Every documented command must be a task in a Taskfile, so that a
  person working locally and continuous integration invoke bootstrap, migrate,
  test, export, and backup the same way.
- **R17.** The model gateway must be stubbable by configuration, so that tests
  run offline and without cost.
- **R17a.** The repository must carry the prompt and tool directories, mounted
  read-only into the workflow container, and the container must fail loudly at
  startup if they are absent (ADRs 0025, 0039), even before any product prompt
  exists.
- **R17b.** The health-check workflow must follow the conventions in ADR 0040:
  named for its job, one failure path, and no figure computed in a node.
- **R18.** A message catalogue for Russian and English must exist in this
  repository and be loaded by the deployed components. A missing translation
  must fail visibly rather than silently render a slug.
- **R19.** Both admins must be able to perform a full restore alone, from the
  written procedure and their own copies of the secrets, with nothing held by
  only one of them.

## Scope

**In scope:**
- The Compose definition of every component and its configuration.
- The household database, its migration mechanism, and an empty schema.
- Ingress and TLS, and the bot's reachable endpoint.
- Installing the identity provider and the reverse proxy, and proving no surface
  is reachable around them. Sign-in methods, roles and the data path are spec 0002.
- The file storage volume and its integrity check.
- Monitoring: health checks, heartbeats for every scheduled job, and alerting.
- The message catalogue.
- Backups, their encryption, their retention, and automatic restore verification.
- Configuration export and drift detection.
- The written rebuild procedure.

**Out of scope (and why):**
- Any ledger table beyond what the migration mechanism needs to prove itself.
  The chart of accounts is spec 0003, and designing it here would split one
  decision across two specs.
- Sign-in methods, roles, row-level security and the data path (spec 0002).
- Any workflow that does product work. One health-check workflow is allowed,
  because we can't verify the deployment claim without it.
- The ledger's own tests. We build the harness here; what it tests arrives with
  the schema in spec 0003.
- Any product workflow beyond the health check. Local mode has to be able to run
  them, but they arrive with their own slices.
- The household app and its screens (spec 0006). PostgREST is deployed here,
  because we have to prove the authentication and row-level-security path before
  anything binds to it.
- The migration to the home server (spec 0010). This slice only guarantees that
  nothing prevents it.

## Acceptance criteria

- [ ] **A1.** Given an empty host with Docker and the repository checked out,
      when the documented bootstrap command is run with a filled `.env`, then
      every component starts and reports healthy without manual intervention.
- [ ] **A2.** Given a running system, when the host is restarted, then every
      component returns to healthy without manual intervention.
- [ ] **A3.** Given the repository, when it is searched for secret values, then
      none are present, and every variable used by the Compose file appears by
      name in `.env.example`.
- [ ] **A3a.** Given the secret inventory, when each entry is checked, then it
      exists in both admins' vaults, and the n8n encryption key specifically is
      present, because a database restore without it silently loses every stored
      credential.
- [ ] **A4.** Given a new migration file, when migrations are applied, then it is
      applied exactly once, and applying twice changes nothing.
- [ ] **A5.** Given a message sent to the registered bot from any Telegram
      account, when the health-check workflow receives it, then a reply is
      produced, which proves the public HTTPS path reaches the automation
      platform.
- [ ] **A5a.** Given a flood of requests to a public surface, when the rate limit
      is exceeded, then further requests are rejected at the edge and the system
      behind it stays responsive.
- [ ] **A6.** Given an unauthenticated browser, when any web surface is requested,
      then no surface content is served and the request reaches the identity
      provider, demonstrated for every deployed surface, including by requesting
      a container's port directly. Who can then sign in is spec 0002.
- [ ] **A7.** Given a file uploaded twice, when it is stored, then one copy exists
      on the volume addressed by its hash, and the second upload is recognised as
      the same file.
- [ ] **A7a.** Given a stored file whose bytes are then corrupted, when the
      integrity check runs, then the mismatch is reported to the admins.
- [ ] **A8.** Given a scheduled job that is prevented from running, when its
      heartbeat window passes, then an alert reaches the admins, verified by
      stopping a job rather than by reasoning about it.
- [ ] **A8a.** Given a string with no Russian translation, when it is rendered,
      then the failure is visible rather than silently showing a slug.
- [ ] **A9.** Given a night has passed, when the backup repository is inspected,
      then a new encrypted snapshot exists locally and offsite, and its contents
      cannot be read without the repository password.
- [ ] **A10.** Given the latest backup, when the verification job runs, then the
      schema migrates, a known query returns its expected result, and a message
      stating the outcome arrives in Telegram.
- [ ] **A11.** Given a verification job that is made to fail deliberately, when it
      runs, then the failure is reported in Telegram rather than passing silently.
- [ ] **A12.** Given a configuration change made through a component's UI, when the
      export command is run, then the change appears as a file difference in this
      repository.
- [ ] **A13.** Given an unexported configuration change, when drift detection runs,
      then the admins receive a report naming the component.
- [ ] **A14.** Given a second empty host, when the rebuild procedure is followed
      using the repository, the secrets and the latest backup, then the resulting
      system passes A1, A5 and A6, performed once rather than reasoned about.
- [ ] **A14a.** Given a clean checkout on a laptop with no domain and no tunnel,
      when the local command is run, then the whole system starts, the seed loads,
      and a message sent to the local bot is captured, which proves the contour
      without a deployment.
- [ ] **A14b.** Given the local deployment, when the delivery mode is switched
      between webhook and polling, then only the environment variable changes and
      no workflow or code is edited.
- [ ] **A14c.** Given the local deployment, when it is inspected, then it uses the
      local bot token and cannot receive the household's messages.
- [ ] **A14d.** Given a fresh deployment with no accounts and the scaffold
      variables set, when the scaffold command is run, then a first admin exists
      and can sign in with email and password, and when it is run again, it
      refuses.
- [ ] **A14e.** Given a required variable removed from the environment, when the
      component starts, then it fails immediately and names the variable, rather
      than starting with a hidden default.
- [ ] **A15.** Given a clean checkout, when the test command is run, then a
      throwaway database is created, migrations apply, the seed loads and the
      suite passes, with no manual setup step.
- [ ] **A16.** Given a deliberately broken migration pushed to a branch, when
      continuous integration runs, then it fails and the failure is reported.
- [ ] **A17.** Given the model gateway configured to the local stub, when a test
      exercises a path that would call a model, then no external request is made.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A component fails to start | Bootstrap fails loudly and names the failing component; nothing reports healthy |
| The offsite backup destination is unreachable | The local backup still succeeds, and the admins are told the offsite copy is missing |
| The restore verification cannot restore | Reported as a failure in Telegram, and the backup is not counted as good |
| The identity provider is down | Web surfaces become unreachable rather than open, and a documented break-glass path gives the admins host-level access |
| Apple's sign-in is unavailable, or the developer membership lapses | Passkey sign-in still works for every member, so nobody is locked out of the books |
| A passkey's device is lost | The owner resets that member's credential, and his own reset path doesn't depend on a single device |
| The public hostname changes | Everyone re-enrols their passkeys, which is documented here because it is otherwise discovered at the worst moment |
| A migration fails halfway | It rolls back, and the recorded applied state doesn't include it |
| Telegram delivers the same update twice | The health-check workflow tolerates it without erroring, in both delivery modes, because polling re-delivers after a crash exactly as webhooks retry |
| A local poller started while the production webhook is set | The two can't be confused, because the local deployment uses its own bot registration and token |

## Ergonomic cost

- **Who does more work:** an admin, once, for the initial setup, and then one
  recurring obligation: glancing at the monthly restore verification result. That
  takes seconds.
- **What queue or obligation it creates:** none for the household. Drift reports
  and failed-heartbeat alerts are events, and each names the component, so an
  admin can act on it instead of adding it to a backlog.
- **What it interrupts, and how often:** only failures, and only for the admins.
  In a healthy month that is one message, the restore verification succeeding.
- **If nobody touches it for a month:** everything keeps running, backups keep
  being taken and verified, and the verification result is the one message that
  proves it. This slice is the part of the system that must not need attention.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **Cost:** the rented host must be a small single VPS, and the whole system,
  excluding model usage, must fit in it.
- **Recovery:** a total host failure must lose at most one night of data.
- **Privacy:** unencrypted household data must never be written to any
  third-party storage.
- **Operability:** for routine failures, an admin must be able to see why
  something failed without reading container logs by hand, because failures come
  to Telegram.

## Open questions

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | The Telegram bot is already registered and its avatar set. Its token needs to reach the shared vault (ADR 0024) before this slice can run | deploy | open |
| Q2 | Which hosting provider and instance size, and which domain name is used? The domain must be stable across the move home, because passkeys are bound to it | deploy | open |
| Q3 | Which EU offsite backup destination - a Hetzner Storage Box, Scaleway or OVHcloud object storage? ADR 0028 excludes non-EU destinations even though restic would encrypt before upload | deploy | open |
| Q4 | Where is the sealed paper copy of the restic password kept, and who else knows (ADR 0024)? | deploy | open |


## Related

- ADRs: 0001, 0002, 0004, 0008, 0009, 0010, 0015, 0017, 0018, 0019, 0020, 0024
- Specs: 0002 (first slice to use this), 0009 (proves R2 and R14 for real)
