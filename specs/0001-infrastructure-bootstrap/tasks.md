---
spec: 0001
created: 2026-09-12
updated: 2026-09-12
---

# 0001 - Tasks

Order matters, because you start a task only once its dependencies are closed.
Each task is one logical commit that leaves the project in a working state.

Legend: `[ ]` not started, `[~]` in progress, `[x]` done, `[-]` dropped

## Tasks

- [x] **T1.** Build the repository skeleton: `Taskfile.yml` with every verb
      declared (some of them failing with "not implemented"), `.env.example`, and
      `compose.yaml` with PostgreSQL only and a `local` profile, so that one
      command brings the system up locally with no domain and no tunnel.
  - Depends on: -
  - Requirements: R1, R2, R9, R9c, R14a, R16a
  - Done when: `task up` starts PostgreSQL on a clean checkout and `task down`
      removes it, and every verb exists.

- [x] **T2.** Wire migrations: dbmate, `db/migrations/`, the committed
      `db/schema.sql` dump, and a migration container that runs before the
      containers that depend on it.
  - Depends on: T1
  - Requirements: R3, R4
  - Done when: `task migrate` applies, applying twice changes nothing, and the
      dump is committed.

- [x] **T3.** Build the test harness: a throwaway database, pgTAP installed,
      `task test`, and the first pgTAP test, which checks that migrations are
      idempotent.
  - Depends on: T2
  - Requirements: R15
  - Done when: `task test` passes from a clean checkout with no manual setup.

- [x] **T4.** Set up continuous integration on GitHub Actions: a PostgreSQL
      service, `task migrate`, `task test`, and a red build on a broken
      migration.
  - Depends on: T3
  - Requirements: R16
  - Done when: a deliberately broken migration on a branch fails CI.

- [x] **T5.** Add the audit skeleton: the `audit_log` shape and a generic trigger
      function, with pgTAP tests that it records before and after images and
      refuses to let an application role change it.
  - Depends on: T3
  - Requirements: R4 (and ADR 0008 for spec 0003 to attach to)
  - Done when: a test table gains auditing by attaching the trigger, and the
      negative tests pass.

- [x] **T6.** Write the seed: the synthetic household's shape, which is three
      members, the account shapes, and the awkward cases the later slices need.
  - Depends on: T2
  - Requirements: R15
  - Done when: `task seed` loads it and `task test` runs against it.

- [x] **T7.** Add file storage: a dedicated volume, content-addressed by SHA-256,
      the metadata table, and the integrity check job.
  - Depends on: T2
  - Requirements: R7
  - Done when: the same bytes stored twice yield one path, and a corrupted byte
      is reported.

- [x] **T8.** Add the i18n catalogue: `i18n/` with this slice's strings in both
      languages, loaded by the components and failing visibly on a missing key.
  - Depends on: T1
  - Requirements: R18
  - Done when: removing a key produces a visible failure rather than a slug.

- [x] **T9.** Add n8n to Compose: the encryption key in the environment, the
      prompt and tool directories mounted read-only and failing loudly if absent,
      and the health-check workflow following ADR 0040's conventions.
  - Depends on: T1
  - Requirements: R17a, R17b
  - Done when: the container starts, the health workflow runs, and removing the
      prompt mount stops startup.

- [x] **T10.** Make Telegram work both ways: the normalisation boundary, long
      polling locally, webhook when deployed, the delivery mode behind one
      variable, the separate local bot token, and idempotent re-delivery.
  - Depends on: T9
  - Requirements: R5, R14b, R14c
  - Done when: a message to the local bot gets a reply with no tunnel, flipping
      the mode changes only `.env`, and a doubled update produces one effect.

- [x] **T11.** Put up ingress and the shell of the boundary: the reverse proxy,
      TLS locally, and every container port unreachable from outside it.
  - Depends on: T9
  - Requirements: R5, R6
  - Done when: requesting a container's port directly is refused. Who can sign in
      is spec 0002's question.

- [x] **T12.** Rate-limit the public paths at the edge.
  - Depends on: T11
  - Requirements: R5a
  - Done when: a flood is rejected at the edge and the system behind it stays
      responsive.

- [x] **T13.** Add monitoring: Uptime Kuma, a health check per service, and a
      heartbeat for every scheduled job.
  - Depends on: T9
  - Requirements: R8
  - Done when: stopping a job produces an alert after its window.

- [x] **T14.** Add backups: restic to a local repository, the nightly job,
      retention, and the offsite destination behind one variable.
  - Depends on: T2, T7
  - Requirements: R10
  - Done when: a snapshot exists, it is ciphertext, and the offsite variable is
      the only difference for the second destination.

- [x] **T15.** Add restore verification: the monthly job, its heartbeat, the
      Telegram report, and a deliberately failed run.
  - Depends on: T14, T13
  - Requirements: R11, R19
  - Done when: a good run reports success, and a sabotaged one reports failure
      and is not counted as good.

- [x] **T16.** Make configuration code: `task export` for workflows, drift
      detection on a schedule, and the report.
  - Depends on: T9
  - Requirements: R12, R13
  - Done when: a UI change appears as a file diff, and leaving it unexported is
      reported.

- [x] **T17.** Write `task scaffold-admin`: the first admin from the environment,
      refusing to run once any account exists, with the password marked initial.
  - Depends on: T2, T11
  - Requirements: R14d, R14e
  - Done when: it works once and refuses the second time, and a component started
      without a required variable names it and exits.

- [x] **T18.** Build the model gateway stub: a local responder that the tests and
      the local deployment point at by configuration, so the suite runs offline
      and for free.
  - Depends on: T3, T9
  - Requirements: R17
  - Done when: the suite exercises a path that would call a model and makes no
      external request.

- [x] **T19.** Rebuild and document: finish `docs/guides/local-development.md`,
      write `docs/guides/operations.md` with the secret inventory and the restore
      procedure, and perform the rebuild once on a second empty host.
  - Depends on: every task above
  - Requirements: R9a, R9b, R14
  - Done when: a second host reaches a working system from the repository, the
      secrets and a backup, recorded with the date.

## Deviation log

When the work had to depart from the plan, record here why it did and what
changed in the spec or the plan as a result.

| Date | What changed | Why |
|---|---|---|
