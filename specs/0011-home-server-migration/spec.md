---
id: 0011
title: Migration to the home server
status: approved
created: 2026-09-12
updated: 2026-09-13
owner: admins
supersedes: []
---

# 0011 — Migration to the home server

## Problem

From the first decision, this system has promised portability: everything that
runs on rented hosting must move to the household's own hardware without being
rewritten (ADR 0002). That promise has never been tested. Until it is, it is a
belief — and beliefs about infrastructure are usually wrong in exactly the places
nobody anticipated.

Three other promises are in the same position. The rebuild procedure claims an
empty host plus this repository plus the secrets plus a backup produces the same
system (ADR 0010). The backups claim to be restorable (ADR 0009). And secret
custody claims that **either** admin can recover alone, from a sealed copy and the
written procedure (ADR 0024) — which has never been attempted by the admin who
did not write it.

This slice is where all four are proven by doing them.

## Why

After this slice the household's financial system runs on hardware it owns, and
the claims above are facts rather than intentions. The rehearsal is the deliverable
as much as the migration: a restore performed by the second admin, unaided.

The measure: the system runs at home, nothing was lost, no workflow was changed,
and the admin who did not build it recovered the database alone.

## Users and scenarios

- **An admin** wants the household's financial data on hardware the household owns.
- **The other admin** wants to know they could recover it alone if they had to.
- **A member** wants nothing to change: the same bot, the same app, the same
  address, the same sign-in.

## Requirements

### The move

- **R1.** The system must run on the home server from the same `docker-compose.yml`
  used on the rented host, with only environment variables and DNS differing
  (ADR 0002).
- **R2.** No workflow, migration, prompt or application file may be modified to
  make the migration work. If one must be, the portability claim was false and the
  change is a finding, recorded before it is made.
- **R3.** The public hostname must not change, because passkeys are bound to it
  (ADR 0032). If it must, every passkey is re-enrolled as part of this slice.
- **R4.** The public edge must remain reachable with no inbound port opened on the
  household network.
- **R5.** All data must be carried over: the database, the file volume, and the
  state of every self-hosted component.
- **R6.** Members must not need to do anything: no re-linking the bot, no new
  account, no re-installing the app.
- **R7.** Monitoring must cover the home server as it covered the rented host,
  including every heartbeat (ADR 0020).
- **R8.** Backups must resume to EU offsite storage from the new location, and the
  first verification after the move must pass (ADR 0009).
- **R9.** The rented host must not be decommissioned until the home server has run
  correctly for a defined period and one verified backup has been taken from it.

### The proofs

- **R10.** The second admin must perform a full restore of the database and the
  file volume into a scratch environment, alone, using only the written procedure
  and their own copy of the secrets (ADR 0024). Any step they cannot complete is a
  defect in the procedure, not in them.
- **R11.** The rebuild claim must be demonstrated: an empty host, this repository,
  the secrets and the latest backup must produce a working system (ADR 0010).
- **R12.** Data integrity after the move must be verified, not assumed: row counts,
  account balances, and the file volume's hashes against the rows that reference
  them.
- **R13.** The residency position must be re-stated after the move: what is now in
  the EU, and which of ADR 0028's gaps have closed — the move makes at least one
  of them cheaper to close.
- **R14.** A rollback to the rented host must be possible until R9's period has
  passed, and must be documented.
- **R15.** The run-in period before decommissioning must be one month of correct
  operation including one passed restore verification.
- **R16.** The edge must not change in this slice. Host and edge are changed
  separately so that a failure is never ambiguous.

## Scope

**In scope:** provisioning the home server, the edge arrangement for the home
phase, carrying the data, cutting over, the integrity verification, the second
admin's unaided restore rehearsal, the rebuild demonstration, monitoring and
backups from the new location, the rollback plan, and updating the procedure with
everything the rehearsal exposed.

**Out of scope (and why):**
- Buying the hardware, and choosing it. That is a household purchase, not a spec.
- High availability, clustering or failover. One machine, honestly.
- Local model inference. It becomes possible here and is its own decision
  (ADR 0029's fourth rung).
- Any product change. If a feature is wanted, it is a different slice; mixing one
  in would make a failed migration ambiguous.

## Acceptance criteria

- [ ] **A1.** Given the home server and this repository, when the documented
      bootstrap is run, then every component starts healthy with no file outside
      `.env` differing from the rented host's deployment.
- [ ] **A2.** Given the migration is complete, when `git status` is inspected, then
      no workflow, migration, prompt or application file was changed to achieve it.
- [ ] **A3.** Given the cutover, when a member sends a capture from Telegram, then it
      is recorded — proving the edge, the bot and the workflows without anyone
      re-linking anything.
- [ ] **A4.** Given the cutover, when a member opens the app and signs in with their
      existing passkey, then they reach it without re-enrolling.
- [ ] **A5.** Given the migration, when balances, row counts and file hashes are
      compared before and after, then they are identical.
- [ ] **A6.** Given the second admin, the sealed secrets and the written procedure,
      when they restore the database and file volume into a scratch environment
      alone, then it succeeds — and every step they had to improvise is recorded
      and fixed in the procedure.
- [ ] **A7.** Given an empty host, this repository, the secrets and the latest
      backup, when the rebuild procedure is followed, then the result passes A1 and
      A3.
- [ ] **A8.** Given the home server, when a night passes, then a backup is taken to
      EU offsite storage and the next verification passes.
- [ ] **A9.** Given every heartbeat, when one job is deliberately stopped, then the
      alert arrives from the new deployment.
- [ ] **A10.** Given the home server has run for the defined period with one
      verified backup, when the rented host is decommissioned, then nothing breaks
      — and until then, the documented rollback has been tested at least once.
- [ ] **A11.** Given the move is complete, when ADR 0028's gap table is reviewed,
      then it is re-stated with what changed.
- [ ] **A12.** Given the migration, when the edge configuration before and after is
      compared, then it is unchanged — the host moved and the edge did not.
- [ ] **A13.** Given the home server has run one month including a passed restore
      verification, when the rented host is decommissioned, then nothing breaks.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| The home connection drops for hours | The bot is unreachable and Telegram retries; captures are not lost, and the alert fires |
| A power cut | Everything returns to healthy on boot, unattended (spec 0001, A2) |
| The home server's disk fails a week later | Restore from offsite, by either admin, per R10's rehearsed procedure |
| The hostname must change after all | Every passkey is re-enrolled in this slice, and members are told before it happens, not after |
| A component behaves differently on the new hardware | A finding against the portability claim; recorded before being worked around |
| The second admin's rehearsal fails | The procedure is wrong. It is fixed and the rehearsal repeated — this is the criterion, not a formality |
| The rented host is needed again mid-migration | The documented rollback, tested beforehand |
| Data differs after the move | Migration is not complete. Nothing is decommissioned until A5 passes |

## Ergonomic cost

- **Who does more work:** both admins, once, for a few hours. Afterwards the
  household owns its uptime — which is a real ongoing cost: a power cut is now
  the household's problem.
- **What queue or obligation it creates:** none new. Operating the home server is
  the same monitoring and backup routine, with the same heartbeats.
- **What it interrupts:** one planned outage during cutover, announced. Nothing
  after.
- **If nobody touches it for a month:** it runs, and the monthly verification is
  the message that says so. The change from the rented phase is that a hardware
  fault is now nearer, which is why R10's rehearsal is the point of this slice.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **Downtime during cutover must be short enough not to matter** — minutes, at a
  time nobody is shopping.
- **No data loss.** The cutover takes a fresh backup first, and a capture sent
  during the window must survive.
- **The household's own hardware, in the EU by construction** — the easiest
  residency win in the whole system (ADR 0028).

## Open questions

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | What is the home server, and does it have the disk redundancy a single machine needs to be honest about? | deploy | open |

## Related

- ADRs: 0002, 0032, 0009, 0010, 0020, 0024, 0028, 0029
- Specs: 0001 (the procedure this proves), 0002, and every slice before it
