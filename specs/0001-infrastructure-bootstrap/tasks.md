---
spec: 0001
created: 2026-09-12
updated: 2026-09-12
---

# 0001 — Tasks

Order matters: a task is started only once its dependencies are closed.
Each task is one logical commit that leaves the project in a working state.

Legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[-]` dropped

## Tasks

- [ ] **T1.** Repository skeleton: `Taskfile.yml` with every verb declared (some
      failing with "not implemented"), `.env.example`, `compose.yaml` with
      PostgreSQL only and a `local` profile — one command brings the system up
      locally with no domain and no tunnel.
  - Depends on: —
  - Requirements: R1, R2, R9, R9c, R14a, R16a
  - Done when: `task up` starts PostgreSQL on a clean checkout and `task down`
      removes it; every verb exists.

- [ ] **T2.** Migrations: dbmate wired, `db/migrations/`, the committed
      `db/schema.sql` dump, a migration container that runs before dependants.
  - Depends on: T1
  - Requirements: R3, R4
  - Done when: `task migrate` applies, applying twice changes nothing, and the
      dump is committed.

- [ ] **T3.** Test harness: a throwaway database, pgTAP installed, `task test`,
      and the first pgTAP test — that migrations are idempotent.
  - Depends on: T2
  - Requirements: R15
  - Done when: `task test` passes from a clean checkout with no manual setup.

- [ ] **T4.** Continuous integration on GitHub Actions: a PostgreSQL service,
      `task migrate`, `task test`, red on a broken migration.
  - Depends on: T3
  - Requirements: R16
  - Done when: a deliberately broken migration on a branch fails CI.

- [ ] **T5.** The audit skeleton: the `audit_log` shape and a generic trigger
      function, with pgTAP tests that it records before and after images and
      refuses modification by an application role.
  - Depends on: T3
  - Requirements: R4 (and ADR 0008 for spec 0003 to attach to)
  - Done when: a test table gains auditing by attaching the trigger, and the
      negative tests pass.

- [ ] **T6.** The seed: the synthetic household's shape — three members, account
      shapes, and the awkward cases the later slices need.
  - Depends on: T2
  - Requirements: R15
  - Done when: `task seed` loads it and `task test` runs against it.

- [ ] **T7.** File storage: a dedicated volume, content-addressed by SHA-256, the
      metadata table, and the integrity check job.
  - Depends on: T2
  - Requirements: R7
  - Done when: the same bytes stored twice yield one path; a corrupted byte is
      reported.

- [ ] **T8.** The i18n catalogue: `i18n/` with this slice's strings in both
      languages, loaded by the components, failing visibly on a missing key.
  - Depends on: T1
  - Requirements: R18
  - Done when: removing a key produces a visible failure, not a slug.

- [ ] **T9.** n8n in Compose: the encryption key in the environment, the prompt
      and tool directories mounted read-only and failing loudly if absent, and
      the health-check workflow following ADR 0040's conventions.
  - Depends on: T1
  - Requirements: R17a, R17b
  - Done when: the container starts, the health workflow runs, and removing the
      prompt mount stops startup.

- [ ] **T10.** Telegram both ways: the normalisation boundary, long polling for
      local, webhook for deployed, the delivery mode behind one variable, the
      separate local bot token, and idempotent re-delivery.
  - Depends on: T9
  - Requirements: R5, R14b, R14c
  - Done when: a message to the local bot gets a reply with no tunnel; flipping
      the mode changes only `.env`; a doubled update produces one effect.

- [ ] **T11.** Ingress and the boundary's shell: the reverse proxy, TLS locally,
      and every container port unreachable from outside it.
  - Depends on: T9
  - Requirements: R5, R6
  - Done when: requesting a container's port directly is refused; who may sign in
      is spec 0002's.

- [ ] **T12.** Rate limiting at the edge on the public paths.
  - Depends on: T11
  - Requirements: R5a
  - Done when: a flood is rejected at the edge and the system behind stays
      responsive.

- [ ] **T13.** Monitoring: Uptime Kuma, health checks per service, and a
      heartbeat for every scheduled job.
  - Depends on: T9
  - Requirements: R8
  - Done when: stopping a job produces an alert after its window.

- [ ] **T14.** Backups: restic to a local repository, the nightly job, retention,
      and the offsite destination behind one variable.
  - Depends on: T2, T7
  - Requirements: R10
  - Done when: a snapshot exists, is ciphertext, and the offsite variable is the
      only difference for the second destination.

- [ ] **T15.** Restore verification: the monthly job, its heartbeat, the Telegram
      report, and a deliberately failed run.
  - Depends on: T14, T13
  - Requirements: R11, R19
  - Done when: a good run reports success; a sabotaged one reports failure and is
      not counted as good.

- [ ] **T16.** Configuration as code: `task export` for workflows, drift
      detection on a schedule, and the report.
  - Depends on: T9
  - Requirements: R12, R13
  - Done when: a UI change appears as a file diff, and leaving it unexported is
      reported.

- [ ] **T17.** `task scaffold-admin`: the first admin from the environment,
      refusing once any account exists, the password marked initial.
  - Depends on: T2, T11
  - Requirements: R14d, R14e
  - Done when: it works once and refuses the second time, and a component started
      without a required variable names it and exits.

- [ ] **T18.** The model gateway stub: a local responder the tests and the local
      deployment point at by configuration, so the suite runs offline and free.
  - Depends on: T3, T9
  - Requirements: R17
  - Done when: the suite exercises a path that would call a model and makes no
      external request.

- [ ] **T19.** The rebuild and the documentation: `docs/guides/local-development.md`
      complete, `docs/guides/operations.md` with the secret inventory and the
      restore procedure, and the rebuild performed once on a second empty host.
  - Depends on: every task above
  - Requirements: R9a, R9b, R14
  - Done when: a second host reaches a working system from the repository, the
      secrets and a backup — recorded with the date.

## Deviation log

| Date | What changed | Why |
|---|---|---|
