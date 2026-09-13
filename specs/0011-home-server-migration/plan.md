---
spec: 0011
created: 2026-09-13
updated: 2026-09-13
---

# 0011 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

**Change one thing at a time, and make the rehearsal the deliverable.** Every
other slice in this repository adds capability; this one adds none and proves
four claims that have only ever been asserted: that the system is portable
(ADR 0002), that the rebuild procedure works (ADR 0010), that the backups
restore (ADR 0009), and that **either** admin can recover alone (ADR 0024).

R16 and A12 say the edge must not change while the host does, and R4 says no
inbound port may be opened at home. Those two are only compatible if the edge
moves **first**, while the rented host is still serving: the outbound tunnel
(ADR 0002's Cloudflare Tunnel, or its named fallbacks) is stood up in front of
the rented host, proven there, and only then does the host underneath it move.
That makes the host migration a single variable — if something breaks after it,
the host is the only thing that changed. So this slice is two cutovers, days
apart, each verified on its own:

1. **Edge cutover, rented host.** The tunnel originates from the rented host;
   `PUBLIC_HOSTNAME` and every certificate arrangement settle here, not during
   the move. Nothing about the host changes.
2. **Host cutover, same edge.** Fresh backup, stop, restore onto the home
   server, re-point the tunnel's origin, verify, done. `.env` and DNS are the
   only things that differ (R1).

The rest is proof, in this order: integrity verification (R12), the second
admin's unaided restore (R10), the rebuild demonstration on an empty host
(R11), a month of correct operation (R15), then decommissioning. The rehearsal
is scheduled early enough that a defect in the procedure is found while the
rented host is still there to fall back to — it is the highest-value item in
the slice, not a sign-off at the end of it.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Edge first on the rented host, then the host | A failure after the move has exactly one candidate cause; satisfies R4 and R16 together | Two planned windows instead of one | **chosen** |
| Move host and edge in one window | One outage, one evening | A failure is ambiguous between the tunnel and the hardware, which is precisely what R16 forbids | rejected |
| Keep a public inbound port at home, no tunnel | No third party terminating TLS | Opens a residential network to the internet and breaks R4; ADR 0002 already decided against it | rejected |
| Run both hosts live, replicating, and switch DNS | Near-zero downtime | Two writable copies of a household ledger, and a split-brain nobody would notice for days. Minutes of downtime is cheap; a divergent ledger is not | rejected |
| Rehearse the restore after decommissioning | Fewer moving parts during the run-in | Removes the fallback exactly when the rehearsal is most likely to expose a defect | rejected |
| Rebuild from backup instead of carrying volumes | Exercises the documented procedure by definition | Slower, and it conflates "the move worked" with "the backup was good". Both are wanted, so both are done — the move carries the data, and A7 rebuilds separately from the backup | rejected as the primary path, kept as A7 |

## Affected areas

Almost nothing in this repository changes, and that is the claim under test.

| Area | This slice | Extended by |
|---|---|---|
| `.env` (not committed) | `PUBLIC_HOSTNAME` unchanged (R3); paths, timezone and the tunnel's own credentials differ | none |
| `compose.yaml`, `db/migrations/`, `workflows/`, `prompts/`, `tools/`, app source | **nothing** — a change here is a portability finding, recorded before it is made (R2, A2) | none |
| Edge configuration | The tunnel arrangement, stood up in step 1 and untouched in step 2 | none |
| `docs/guides/operations.md` | The rebuild record and break-glass rehearsal records gain dated rows; the break-glass second route is re-stated for a home server that has no provider console; the rollback procedure is added | spec-less maintenance thereafter |
| `docs/guides/deployment.md` | Corrected by everything the rehearsal exposes — the only reliable source of what a procedure is missing | phase 11 is its last scheduled update |
| `docs/architecture/decisions/0028-*.md` | Its tier-3 gap table re-stated with what the move closed (R13, A11) | revisited if a gap closes later |

## Contracts and data

- **`PUBLIC_HOSTNAME` is the contract with every member's device.** Passkeys are
  bound to it (ADR 0032) and the Telegram webhook is registered against it. It
  does not change (R3); if it ever must, passkey re-enrolment is announced before
  the move, not discovered after it.
- **The restic repositories do not change with the host.** `RESTIC_REPOSITORY`
  and `BACKUP_OFFSITE_REPOSITORY` point at the same repositories the rented host
  used — `operations.md` step 2 already says so, and this slice is the first time
  it matters.
- **The integrity comparison is a contract, not a spot check** (R12): per-account
  balances from `v_account_balance`, `count(*)` for every table, and every stored
  file re-hashed against its `file` row by `scripts/file-check-integrity.sh`.
  Captured to a file before the cutover and after it, and diffed. A difference
  means the migration is not complete (A5) and nothing is decommissioned.
- **Break-glass loses a route at home.** `operations.md` names two: an SSH key per
  admin, and the hosting provider's rescue console. A home server has no Hetzner
  console; unless the machine has out-of-band management, the second route becomes
  **physical access to the machine** — stronger in substance, different in kind,
  and it must be written down as such rather than left as a stale sentence about a
  provider that no longer exists in this deployment.
- **No new table, view, workflow or environment variable** is introduced by this
  slice. `docs/architecture/data-model.md` is untouched.

## Migration and compatibility

**The cutover, in order.** Announce the window. Take a fresh backup and assert
the snapshot exists. Capture the integrity baseline (R12). Stop the rented
stack, so nothing writes to two places. Carry the volumes — database dump, the
file volume, and every self-hosted component's state (R5) — restore onto the
home server, `task up`, re-point the tunnel origin, capture the integrity
comparison, then unstop the window. Target: minutes, at an hour nobody is
shopping.

**Nothing is lost in the window.** The tunnel's origin is down, so Telegram
receives a 5xx and retries the update on its own schedule; a capture sent during
the window arrives afterwards. This is the same property spec 0001's delivery
modes were built around (ADR 0033), and it is asserted by sending a capture
deliberately mid-window and confirming it lands.

**Rollback is real until R9's period has passed.** The rented host is kept
running and its volumes intact; rolling back is re-pointing the tunnel origin
back to it and restoring anything captured at home in the meantime. It is
**tested once during the run-in**, not merely written down (A10) — a rollback
that has never been exercised is a paragraph, not a path.

**What is different at home**, and none of it is a product change:

- **Dynamic addressing.** The residential connection's address changes; the
  outbound tunnel makes that irrelevant for ingress, which is half the reason
  ADR 0002 chose it. Nothing in this system is IP-allowlisted.
- **A residential connection's reliability.** Outages are now the household's,
  not a data centre's. The bot is unreachable, Telegram retries, and the
  heartbeat alert fires — that is the designed behaviour, and it is the same
  alert path spec 0001 T13 already proved.
- **Power loss.** Everything must return to healthy on boot unattended
  (spec 0001 A2), which the restart policies already give. Whether the machine
  is on a UPS is a household purchase, not a spec.
- **Physical access.** A security property (nobody else's hypervisor holds the
  books) and a risk (theft, fire, a spilled drink) at once. It is why the offsite
  backup stops being a formality here.
- **Disk redundancy (Q1).**

**Q1 gates provisioning and the decommissioning decision, not this plan.** If
the answer is that the machine has redundancy, nothing changes. If it is that it
has none, the plan does not stall: the offsite backup becomes the *only*
redundancy, that is written plainly in `operations.md` rather than glossed, the
verification cadence stays monthly at minimum, and keeping the rented host — or
a cheap replacement of it — as a warm fallback becomes a decision the household
makes with the true picture in front of it. What is not acceptable is a single
non-redundant disk described as though it were more than that.

## Verification strategy

Most of this slice cannot be a test script, and pretending otherwise would be
the dishonesty ADR 0015 exists to prevent. Three things are scripted, the rest
are **recorded**: a dated row in `docs/guides/operations.md`, naming who
performed it, what they did, and what it exposed — exactly the shape the rebuild
record and the break-glass rehearsal record already use.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | `task up` on the home server from a clean clone; every container reports healthy. Then a file-by-file diff of the two checkouts, asserting `.env` is the only difference |
| A2 | The same diff scoped to `workflows/`, `db/migrations/`, `prompts/`, `tools/` and the app source, asserted byte-identical, plus a clean `git status`. Any change needed to make the move work is written down as a portability finding **before** it is made (R2) |
| A3 | A member sends a real capture from their own Telegram account after the cutover and it is recorded, with nobody having re-linked anything. Scripted health checks (`scripts/test-health-check.sh`) prove the path is up; a person proves R6 |
| A4 | The same member opens the app and signs in with the passkey enrolled before the move, with no re-enrolment prompt. Holds only because `PUBLIC_HOSTNAME` did not change (R3) |
| A5 | The integrity comparison above: balances per account, `count(*)` per table, and `scripts/file-check-integrity.sh` over every stored file, captured before and after and diffed. Any difference blocks every later step |
| A6 | **The rehearsal.** The second admin, alone, with only the sealed copy and `operations.md`, restores the database and file volume into a scratch environment. Every step they improvise is written down as it happens, fixed in the procedure, and the rehearsal repeated until nothing is improvised. Recorded, dated, in the rebuild record |
| A7 | The rebuild demonstration: a genuinely empty host, this repository, the secrets and the latest backup, following `operations.md` unchanged. Passes when it satisfies A1 and A3 on that host. Recorded |
| A8 | Overnight from the home server: assert a new snapshot in the offsite repository (`scripts/restic-run.sh snapshots`), then that the next `task verify-restore` passes and its heartbeat lands in Kuma |
| A9 | Sabotage, against the home deployment rather than assumed to carry over: stop one scheduled job, wait out its window, assert the alert arrives (`scripts/test-heartbeat-alert.sh`'s pattern, run for real) |
| A10 | Two parts, both recorded: the documented rollback is exercised once during the run-in — cut back to the rented host, confirm a capture lands, cut forward again, with the elapsed time noted — and decommissioning happens only after A13 |
| A11 | ADR 0028's tier-3 table edited in place, stating which gaps the move closed and which it only made cheaper to close. Reviewed as a diff, like any other decision change |
| A12 | The edge configuration captured before the host move and compared after: unchanged by construction, because the edge moved in step 1 and the host in step 2. The comparison is the check that the two steps really were separate |
| A13 | A dated record of one month's correct operation containing a passed restore verification. Kuma's own heartbeat history for that month is the evidence; the record cites it. A13 is A10's run-in half with R15's period made explicit — they close together, from the same record |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The household loses access to its own books mid-move | low, and the worst outcome in the slice | The rented host stays up with its volumes intact until A13; the rollback is tested (A10); the cutover starts with a fresh verified backup |
| The rehearsal (A6) fails and the procedure needs real work | **high, and it is the point** | Scheduled while the rented host is still there. A failed rehearsal is a finding, not a delay: the procedure is fixed and it is repeated, per the spec's own edge-case table |
| The tunnel changes how certificates are issued at the origin | medium | Settled and proven in step 1, on the rented host, where a failure costs nothing. Whatever arrangement results is what A12 then holds constant |
| Q1 resolves to "no redundancy" | medium | Does not block the move; changes what `operations.md` claims and whether the rented host is really decommissioned. See above |
| Something behaves differently on the new hardware (architecture, kernel, storage driver) | medium | Every container image is pinned; a difference is recorded as a portability finding (R2) before any workaround, which is the whole value of running A1 and A2 as a diff rather than a feeling |
| Break-glass route 2 quietly stops existing at home | medium | Named here and re-stated in `operations.md` as part of the slice; a stale sentence about a provider console the deployment no longer has is worse than no sentence |
| The run-in month passes without anyone checking, and decommissioning is done on a feeling | low | A13 is closed by a record citing Kuma's heartbeat history, not by recollection |

## ADRs required

None new. This slice executes decisions already accepted — 0002 (portability and
the tunnel edge), 0009, 0010, 0020, 0024 and 0032 — and its output is edits to
two of them rather than a new one:

- **ADR 0028's tier-3 gap table is re-stated** (R13, A11). The ADR already says
  the residency direction is revisited when the home server arrives; this is that
  revisit, and the model gateway's third rung — local inference — becomes possible
  here, though choosing it is explicitly out of scope.
- **ADR 0024's break-glass second route** needs its home equivalent named, since
  "the hosting provider's rescue console" describes a provider this deployment no
  longer has.
