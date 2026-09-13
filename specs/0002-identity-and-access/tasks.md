---
spec: 0002
created: 2026-09-12
updated: 2026-09-12
---

# 0002 — Tasks

Order matters: a task is started only once its dependencies are closed.
Each task is one logical commit that leaves the project in a working state.

Legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[-]` dropped

## Tasks

- [x] **T1.** Real identity tables: `member`, `member_identity`,
      `member_channel`; `admin_account` (spec 0001 T17) dropped outright.
  - Depends on: —
  - Requirements: R4, R6a, R6b, R6d, R7
  - Done when: the migration applies and reverses cleanly; `admin_account` no
      longer exists; pgTAP confirms the three tables' shapes match
      `docs/architecture/data-model.md`.

- [x] **T2.** The six database roles from R15b, created with no grants yet —
      the roles exist and are enumerable before anything depends on their
      privileges.
  - Depends on: T1
  - Requirements: R15b
  - Done when: `select rolname from pg_roles` lists exactly `anon`,
      `hh_member`, `hh_admin`, `hh_agent`, `hh_report`, `authenticator`, no
      more and no fewer.

- [x] **T3.** Row-level security on every table spec 0001 created (`file`,
      `audit_log`) plus the three identity tables: default-deny, then the
      grants R15b actually names for each role.
  - Depends on: T2
  - Requirements: R8, R9, R14, R15b, R15c
  - Done when: pgTAP, impersonating each role in turn, proves exactly what
      R15b says it may and nothing else; A14 (no token reads nothing) and A23
      (grants match R15b verbatim, checked against
      `information_schema.role_table_grants`) both pass.

- [x] **T4.** A scaffold table standing in for the ledger, deliberately —
      spec 0003 brings the real transaction/posting tables and policies; this
      slice cannot wait for them to prove that member-vs-admin write policies
      work at all.
  - Depends on: T3
  - Requirements: R9, R10, R11, R12, R13
  - Done when: pgTAP, impersonating `hh_member` and `hh_admin` in turn,
      proves R9–R13's shape (everyone reads, only admin deletes/corrects
      structurally, any member reclassifies, a member confirms only their
      own unconfirmed row, no raw posting-shaped insert survives under any
      role) — closes A11, A12, A13, A30, A31 against the scaffold; A24
      (agent insert with no acting member fails) is proven here too, since it
      needs only `hh_agent` and a writable table, not the real ledger.

- [x] **T5.** Authentik as a container: its own separate database (ADR 0004),
      configured entirely by committed blueprints (ADR 0010) — the
      `admin`/`household` groups, a passkey policy, no Apple source yet.
  - Depends on: T2
  - Requirements: R2, R3, R5, R6, R7, R17
  - Done when: `task up` brings Authentik up from the blueprints alone, no
      click surviving a rebuild; a passkey can be enrolled and used to sign
      in; A28 (revoke one of two passkeys) and A29 (a non-device-bound admin
      factor still works) pass against it directly.

- [x] **T6.** Email and password sign-in, rate-limited and lockable; no
      self-service reset.
  - Depends on: T5
  - Requirements: R1, R1a, R3, R3a, R3b, R3c
  - Done when: A1 (an admin-created member signs in with nothing else enrolled beforehand),
      A4 (lockout after repeated failure, logged), and A5 (no outbound email
      anywhere in the stack; a reset is admin-performed and audited) pass.

- [x] **T7.** The token bridge (ADR 0041): resolves an Authentik identity to
      a member via `member_identity` and a role via group membership, mints a
      short-lived PostgREST JWT — tested in isolation, nothing wired through
      it yet.
  - Depends on: T3, T6
  - Requirements: R15, R15a, R16a
  - Done when: given a fabricated set of forward-auth headers for a known
      member, the bridge returns a token whose `role` and `member_id` claims
      are correct; given a subject with no `member_identity` row, it refuses
      outright (A22) rather than minting anything.

- [x] **T8.** PostgREST joins the stack, reachable only through the proxy,
      accepting only tokens the bridge mints.
  - Depends on: T7
  - Requirements: R15, R16b
  - Done when: a request straight to PostgREST's own port is refused (A26,
      same pattern as spec 0001 T11); a request through the proxy with a
      tampered-role token (A15) or an expired one (A16) is rejected by
      PostgREST itself, not by the bridge.

- [x] **T9.** The full proxy path — Authentik forward-auth → token bridge →
      PostgREST — wired for the app's own path and proven with real
      impersonation-by-role requests against T3/T4's tables and policies.
  - Depends on: T4, T8
  - Requirements: R16, R16a, R16c, R17c
  - Done when: A25 (no bearer token anywhere reachable from a browser
      context — this slice's own test harness stands in for the app, which
      is spec 0006's) and R16c's documented local-token command both pass;
      the same request, run with `hh_member` vs `hh_admin` sessions, gets the
      different answers T4's policies predict.

- [x] **T10.** Every other administrative surface behind the same boundary,
      one at a time: n8n (forward-auth plus its own documented password),
      Uptime Kuma (its own auth disabled), Authentik's own admin
      (self-referential, per R17a's table).
  - Depends on: T9
  - Requirements: R17, R17a, R17b, R17c
  - Done when: A9 (passkey alone reaches admin surfaces with Apple disabled),
      A33 (every surface usable with no paid Authentik feature), and A34 (one
      sign-in reaches every surface, n8n's own password the one documented
      exception) all pass, enumerated per surface.

- [ ] **T11.** Apple as a federated source, behind a flag (Q1 is open, not
      blocking): sign-in attaches to an existing account, never creates one.
  - Depends on: T6
  - Requirements: R1b, R1c, R3a
  - Done when: A1a (the first Apple sign-in auto-attaches by matching email,
      no admin step), A2 (a passkey and an Apple ID both attach to the same
      account), A6 (Apple SSO across two surfaces), and A7 (two sign-ins with
      Hide My Email land on one account) pass; if Q1 is still unresolved when
      this task is reached, it is skipped and logged in the deviation log
      below, not blocked on.

- [x] **T12.** Telegram linking: an admin links a member's Telegram id; an
      unlinked id reaches nothing.
  - Depends on: T9
  - Requirements: R6a, R6c, R6d
  - Done when: A18 (unlinked id: nothing written, nothing revealed, the
      attempt logged), A19 (a capture attributes to the member, and survives
      a re-link to a different account unchanged), and A20 (a member with no
      channel linked still reaches the app path) pass.

- [x] **T13.** An admin creates a member's account — in Authentik and in
      `member`/`member_identity` together, a temporary password inert until
      changed (R1, R1a, R1d) — and the scaffold becomes that same mechanism's
      first invocation: create the very first admin, refusing once any
      account exists.
  - Depends on: T5, T7
  - Requirements: R1, R1a, R1d, R14a, R14b, R14c
  - Done when: A1b (the temporary password reaches nothing until changed,
      and does not work again after), A21 (the scaffold works once, refuses a
      second time, same pattern as spec 0001 T17's own test), and A17 (a
      deactivated member's sign-in fails and the bridge stops minting for
      them immediately, not after a token expires) all pass — A1 itself is
      already closed by T6, which created its fixture the same admin-only way.

- [x] **T14.** Break-glass: an SSH key per admin, both admins holding both
      routes, documented and rehearsed once.
  - Depends on: T13
  - Requirements: R6e, R18
  - Done when: A27 — Authentik stopped, SSH access and a direct `psql`
      session both still work — performed once, recorded with the date, the
      same way spec 0001 T19 recorded its rebuild.

## Coverage check

Every `A*` from the spec is closed by exactly the tasks above: A1/A4/A5→T6,
A1a/A2/A6/A7→T11, A1b→T13, A3→T10 (needs a real admin-gated Proxy Provider to
refuse against), A8→T5, A9/A33/A34→T10, A10→T4, A11–A13→T4, A14/A23→T3,
A15/A16→T8, A17→T13, A18–A20→T12, A21→T13, A22→T7, A24→T4, A25→T9, A26→T8,
A27→T14, A28/A29→T5, A30/A31→T4, A32 is tracked but not closeable until spec
0006 builds the app — carried forward explicitly rather than marked done here.

## Deviation log

If the work had to depart from the plan, record the reason here and what
changed in the spec or the plan.

| Date | What changed | Why |
|---|---|---|
| 2026-09-13 | T11 (Apple as a federated source) skipped, per its own done-when clause | Q1 is still open: no Apple Developer Program membership is confirmed held, and `APPLE_SERVICES_ID`/`APPLE_TEAM_ID`/`APPLE_KEY_ID`/`APPLE_PRIVATE_KEY` are all unset in `.env`. Email and password (T6) already onboards everyone (ADR 0032); nothing else in this slice depends on T11. Revisit once Q1 resolves — the task itself, its requirements (R1b, R1c, R3a) and acceptance criteria (A1a, A2, A6, A7) are unchanged, only deferred. |
