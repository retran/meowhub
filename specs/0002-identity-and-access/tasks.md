---
spec: 0002
created: 2026-09-12
updated: 2026-09-12
---

# 0002 - Tasks

Order matters, because you start a task only once its dependencies are closed.
Each task is one logical commit that leaves the project in a working state.

Legend: `[ ]` not started, `[~]` in progress, `[x]` done, `[-]` dropped

## Tasks

- [x] **T1.** Create the real identity tables, `member`, `member_identity`, and
      `member_channel`, and drop `admin_account` (spec 0001 T17) outright.
  - Depends on: -
  - Requirements: R4, R6a, R6b, R6d, R7
  - Done when: the migration applies and reverses cleanly, `admin_account` no
      longer exists, and pgTAP confirms the three tables' shapes match
      `docs/architecture/data-model.md`.

- [x] **T2.** Create the six database roles from R15b with no grants yet, so
      that the roles exist and can be listed before anything depends on their
      privileges.
  - Depends on: T1
  - Requirements: R15b
  - Done when: `select rolname from pg_roles` lists exactly `anon`,
      `hh_member`, `hh_admin`, `hh_agent`, `hh_report`, `authenticator`, no
      more and no fewer.

- [x] **T3.** Turn on row-level security for every table spec 0001 created
      (`file`, `audit_log`) plus the three identity tables: default-deny first,
      then the grants R15b names for each role.
  - Depends on: T2
  - Requirements: R8, R9, R14, R15b, R15c
  - Done when: pgTAP, impersonating each role in turn, proves exactly what
      R15b allows it and nothing else, and A14 (no token reads nothing) and A23
      (grants match R15b verbatim, checked against
      `information_schema.role_table_grants`) both pass.

- [x] **T4.** Add a scaffold table that stands in for the ledger. Spec 0003
      brings the real transaction and posting tables and their policies, and
      this slice can't wait for them to prove that member-against-admin write
      policies work at all.
  - Depends on: T3
  - Requirements: R9, R10, R11, R12, R13
  - Done when: pgTAP, impersonating `hh_member` and `hh_admin` in turn, proves
      the shape R9 to R13 describe: everyone reads, only an admin deletes or
      corrects structurally, any member reclassifies, a member confirms only
      their own unconfirmed row, and no raw posting-shaped insert survives under
      any role. That closes A11, A12, A13, A30, and A31 against the scaffold,
      and A24 (an agent insert with no acting member fails) is proven here too,
      because it needs only `hh_agent` and a writable table rather than the real
      ledger.

- [x] **T5.** Run Authentik as a container with its own separate database (ADR
      0004), configured entirely by committed blueprints (ADR 0010): the `admin`
      and `household` groups, a passkey policy, and no Apple source yet.
  - Depends on: T2
  - Requirements: R2, R3, R5, R6, R7, R17
  - Done when: `task up` brings Authentik up from the blueprints alone with no
      click surviving a rebuild, a passkey can be enrolled and used to sign in,
      and A28 (revoke one of two passkeys) and A29 (a non-device-bound admin
      factor still works) pass against it directly.

- [x] **T6.** Add email and password sign-in, rate-limited and lockable, with no
      self-service reset.
  - Depends on: T5
  - Requirements: R1, R1a, R3, R3a, R3b, R3c
  - Done when: A1 (an admin-created member signs in with nothing else enrolled beforehand),
      A4 (lockout after repeated failure, logged), and A5 (no outbound email
      anywhere in the stack, and a reset that an admin performs and the audit
      records) pass.

- [x] **T7.** Build the token bridge (ADR 0041): it resolves an Authentik
      identity to a member through `member_identity` and to a role through group
      membership, then mints a short-lived PostgREST JWT. Test it in isolation,
      with nothing wired through it yet.
  - Depends on: T3, T6
  - Requirements: R15, R15a, R16a
  - Done when: given a fabricated set of forward-auth headers for a known
      member, the bridge returns a token whose `role` and `member_id` claims
      are correct, and given a subject with no `member_identity` row, it refuses
      outright (A22) rather than minting anything.

- [x] **T8.** Add PostgREST to the stack, reachable only through the proxy and
      accepting only tokens the bridge mints.
  - Depends on: T7
  - Requirements: R15, R16b
  - Done when: a request straight to PostgREST's own port is refused (A26,
      same pattern as spec 0001 T11), and a request through the proxy with a
      tampered-role token (A15) or an expired one (A16) is rejected by
      PostgREST itself rather than by the bridge.

- [x] **T9.** Wire the full proxy path, from Authentik forward-auth to the token
      bridge to PostgREST, for the app's own path, and prove it with real
      requests that impersonate each role against T3 and T4's tables and
      policies.
  - Depends on: T4, T8
  - Requirements: R16, R16a, R16c, R17c
  - Done when: A25 (no bearer token is reachable from a browser context, with
      this slice's own test harness standing in for the app, which is spec
      0006's job) and R16c's documented local-token command both pass, and the
      same request run with an `hh_member` session and an `hh_admin` session
      gets the different answers T4's policies predict.

- [x] **T10.** Put every other administrative surface behind the same boundary,
      one at a time: n8n (forward-auth plus its own documented password), Uptime
      Kuma (its own authentication disabled), and Authentik's own admin
      (self-referential, per R17a's table).
  - Depends on: T9
  - Requirements: R17, R17a, R17b, R17c
  - Done when: A9 (passkey alone reaches admin surfaces with Apple disabled),
      A33 (every surface usable with no paid Authentik feature), and A34 (one
      sign-in reaches every surface, with n8n's own password as the one
      documented exception) all pass, surface by surface.

- [ ] **T11.** Add Apple as a federated source behind a flag (Q1 is open but
      doesn't block): a sign-in attaches to an existing account and never
      creates one.
  - Depends on: T6
  - Requirements: R1b, R1c, R3a
  - Done when: A1a (the first Apple sign-in auto-attaches by matching email,
      with no admin step), A2 (a passkey and an Apple ID both attach to the same
      account), A6 (Apple SSO across two surfaces), and A7 (two sign-ins with
      Hide My Email land on one account) pass. If Q1 is still unresolved when
      this task is reached, skip it and record that in the deviation log below
      rather than blocking on it.

- [x] **T12.** Build Telegram linking: an admin links a member's Telegram id,
      and an unlinked id reaches nothing.
  - Depends on: T9
  - Requirements: R6a, R6c, R6d
  - Done when: A18 (an unlinked id writes nothing, reveals nothing, and the
      attempt is logged), A19 (a capture attributes to the member and survives
      a re-link to a different account unchanged), and A20 (a member with no
      channel linked still reaches the app path) pass.

- [x] **T13.** Let an admin create a member's account, in Authentik and in
      `member` and `member_identity` together, with a temporary password that is
      inert until changed (R1, R1a, R1d). The scaffold becomes that same
      mechanism's first invocation: it creates the very first admin and refuses
      once any account exists.
  - Depends on: T5, T7
  - Requirements: R1, R1a, R1d, R14a, R14b, R14c
  - Done when: A1b (the temporary password reaches nothing until changed, and
      doesn't work again afterwards), A21 (the scaffold works once and refuses a
      second time, same pattern as spec 0001 T17's own test), and A17 (a
      deactivated member's sign-in fails and the bridge stops minting for them
      immediately rather than after a token expires) all pass. A1 itself is
      already closed by T6, which created its fixture the same admin-only way.

- [x] **T14.** Set up break-glass access: an SSH key per admin, both admins
      holding both routes, documented and rehearsed once.
  - Depends on: T13
  - Requirements: R6e, R18
  - Done when: A27 passes, with Authentik stopped while SSH access and a direct
      `psql` session both still work, performed once and recorded with the date,
      the same way spec 0001 T19 recorded its rebuild.

## Coverage check

The tasks above close every `A*` in the spec, and this mapping says which task
closes which criterion: A1, A4, A5 -> T6; A1a, A2, A6, A7 -> T11; A1b -> T13;
A3 -> T10 (it needs a real admin-gated Proxy Provider to refuse against);
A8 -> T5; A9, A33, A34 -> T10; A10 -> T4; A11 to A13 -> T4; A14, A23 -> T3;
A15, A16 -> T8; A17 -> T13; A18 to A20 -> T12; A21 -> T13; A22 -> T7;
A24 -> T4; A25 -> T9; A26 -> T8; A27 -> T14; A28, A29 -> T5; A30, A31 -> T4.
A32 is tracked here but can't be closed until spec 0006 builds the app, so we
carry it forward explicitly rather than mark it done.

## Deviation log

When the work had to depart from the plan, record here why it did and what
changed in the spec or the plan as a result.

| Date | What changed | Why |
|---|---|---|
| 2026-09-13 | T11 (Apple as a federated source) skipped, per its own done-when clause | Q1 is still open: nobody has confirmed an Apple Developer Program membership is held, and `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` are all unset in `.env`. Email and password (T6) already onboards everyone (ADR 0032), and nothing else in this slice depends on T11. We revisit it once Q1 resolves; the task itself, its requirements (R1b, R1c, R3a) and its acceptance criteria (A1a, A2, A6, A7) are unchanged, only deferred. |
