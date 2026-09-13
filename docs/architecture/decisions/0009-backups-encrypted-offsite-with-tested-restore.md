---
id: 0009
title: Nightly encrypted backups to an offsite repository, with restore verified on a schedule
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0009 — Nightly encrypted backups to an offsite repository, with restore verified on a schedule

## Context

ADR 0004 makes PostgreSQL the asset: years of household expenses, the merchant
registry, and the audit log that explains them. Everything else in the system —
workflows, containers, the app — is reproducible from this repository. The
database is not.

The system chose self-hosting and no managed services (ADR 0002), which means
nobody else is taking backups. Two specific risks follow from the rest of the
design:

- **The home server phase concentrates the risk.** A single machine in a flat,
  with household hardware's reliability, holding the only copy.
- **Bulk operations can corrupt quietly.** A bad statement reconciliation can
  rewrite many entries at once (vision principle 8). Restoring "yesterday" is
  the recovery path, so backups must go back further than the time it takes to
  notice.

A backup that has never been restored is a belief, not a backup.

## Decision

**Nightly, encrypted, offsite, with the restore actually tested.**

- **What is backed up:** a logical `pg_dump` of the meowhub database (ledger,
  members, merchants, statements, audit log) and of the databases n8n and Authentik
  keep their own state in; plus the volumes holding uploaded
  receipts and statements. Workflow JSON, migrations and the household app itself
  live in this repository and are therefore backed up by git — that export is
  part of the routine, not an afterthought.
- **What is not backed up here:** secrets. The `.env` file and the bot, model and
  provider keys live in each admin's password manager. A backup that contains the
  keys to itself is a single point of compromise.
- **Encrypted before it leaves the host.** Backups are encrypted client-side with
  **restic**, so the storage provider holds ciphertext only. This is what makes
  using cheap third-party storage compatible with the privacy principle; the
  repository password lives in the password manager, not on the server.
- **Two destinations:** a local copy on the host for fast restores, and an
  offsite S3-compatible repository (Backblaze B2, Cloudflare R2 or a Hetzner
  Storage Box) for everything else. In the home-server phase the offsite copy is
  the only thing standing between the household and a dead disk, so it is not
  optional.
- **Retention:** 7 daily, 4 weekly, 12 monthly. Deep enough that a corruption
  noticed weeks later is still recoverable, small enough to be free in practice
  at this data size.
- **Restore is verified monthly, automatically:** the latest backup is restored
  into a scratch database and checked — the schema migrates, row counts are
  sane, and a known query returns a known answer. A failed verification alerts
  the admins in Telegram, through the same bot. An unverified backup counts as no
  backup.
- **The restore procedure is written down** and rehearsed as part of the
  home-server migration slice — that slice *is* a full restore onto new
  hardware, which is the only honest test.

## Alternatives

| Option | Why rejected |
|---|---|
| Provider snapshots of the VPS | Convenient, but tied to the provider — worthless the moment the system moves home, which is the phase with the highest risk. Also unencrypted from the household's point of view, and not application-consistent |
| pgBackRest with WAL archiving and point-in-time recovery | The technically superior answer: recovery to the minute rather than the night. Rejected as disproportionate to run and monitor for a household ledger where losing a day means re-entering a few expenses. Revisit if the ledger ever becomes something a business depends on |
| Borg instead of restic | Equally good and equally encrypted; restic is chosen for first-class S3-compatible backends without an intermediate host |
| Nightly dumps to a local disk only | Survives a mistake, not a fire, a theft or a failed disk. Exactly the case the home-server phase makes likely |
| Dumping to a cloud drive (iCloud, Dropbox) unencrypted | Puts the full household financial history, receipts included, in plaintext on someone else's storage |
| Trusting git plus "the data can be re-entered" | The ledger cannot be re-entered. That is the entire point of it |

## Consequences

**Good:**
- The one irreplaceable thing in the system has an encrypted copy somewhere
  else, every night.
- Monthly verification means the backup's existence is a fact, not an assumption.
- The migration slice is de-risked: moving home is a restore we have already
  practised.

**Bad, and the price we accept:**
- Logical dumps mean recovery to the last night, not to the last minute. Up to a
  day of captures can be lost, and would have to be re-entered.
- The restic repository password and the secrets in the password manager become
  critical: losing them loses the backups. That risk moves to the password
  manager's own recovery story, deliberately.
- Nightly dumps and monthly verification restores are moving parts that can fail
  silently, which is why failure alerts into Telegram are part of the decision
  rather than a nice-to-have.
- A small ongoing storage cost, and dump duration growing with the audit log —
  the pruning valve in ADR 0008 is the answer if it ever matters.

**What becomes harder to change later:**
- Little. Logical dumps are the portable format; moving to pgBackRest later is
  additive and does not invalidate the existing repository.
