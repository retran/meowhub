---
id: 0009
title: Nightly encrypted backups to an offsite repository, with restore verified on a schedule
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0009 - Nightly encrypted backups to an offsite repository, with restore verified on a schedule

## Context

ADR 0004 makes PostgreSQL the asset, because it holds years of household
expenses, the merchant registry and the audit log that explains them. We can
reproduce everything else in the system from this repository - workflows,
containers, the app - and we cannot reproduce the database.

We chose self-hosting and no managed services (ADR 0002), so nobody else takes
backups for us. Two risks follow from the rest of the design:

- The home server phase concentrates the risk in one machine in a flat, with
  household hardware's reliability, holding the only copy.
- A bulk operation can corrupt the ledger quietly, because a bad statement
  reconciliation rewrites many entries at once (vision principle 8). Restoring
  yesterday is the recovery path, so backups have to reach back further than the
  time it takes somebody to notice.

Until a backup has been restored once, nobody knows whether it can be, so we
treat an untested backup as no backup at all.

## Decision

We take a nightly encrypted backup to an offsite repository and test the restore
on a schedule. Seven rules define it:

- We back up a logical `pg_dump` of the meowhub database (ledger, members,
  merchants, statements, audit log) and of the databases n8n and Authentik keep
  their own state in, plus the volumes that hold uploaded receipts and
  statements. Workflow JSON, migrations and the household app live in this
  repository, so git backs them up, and exporting them is part of the routine
  rather than an afterthought.
- We keep secrets out of the backup. The `.env` file and the bot, model and
  provider keys live in each admin's password manager, because a backup that
  contains the keys to itself is a single point of compromise.
- We encrypt before anything leaves the host, client-side with **restic**, so
  the storage provider holds ciphertext only. That is what lets us use cheap
  third-party storage and still keep the privacy principle, and the repository
  password lives in the password manager and not on the server.
- We write to two destinations: a local copy on the host for fast restores, and
  an offsite S3-compatible repository (Backblaze B2, Cloudflare R2 or a Hetzner
  Storage Box) for everything else. In the home-server phase the offsite copy is
  the only thing between the household and a dead disk, so it is not optional.
- We retain 7 daily, 4 weekly and 12 monthly snapshots, which is deep enough to
  recover corruption noticed weeks later and small enough to cost nothing in
  practice at this data size.
- We verify the restore monthly and automatically: the job restores the latest
  backup into a scratch database and checks it, so the schema migrates, row
  counts are sane, and a known query returns a known answer. A failed check
  alerts the admins in Telegram, through the same bot.
- We write the restore procedure down and rehearse it in the home-server
  migration slice, because that slice *is* a full restore onto new hardware,
  which is the only honest test.

## Alternatives

| Option | Why rejected |
|---|---|
| Provider snapshots of the VPS | Convenient, but tied to the provider, so they are worthless the moment the system moves home, which is the phase with the highest risk. They are also unencrypted from the household's point of view, and not application-consistent |
| pgBackRest with WAL archiving and point-in-time recovery | The technically superior answer, because it recovers to the minute instead of to the night. We rejected it as too much to run and monitor for a household ledger where losing a day means re-entering a few expenses. Revisit it if the ledger ever becomes something a business depends on |
| Borg instead of restic | Equally good and equally encrypted. We chose restic for its first-class S3-compatible backends, which need no intermediate host |
| Nightly dumps to a local disk only | Survives a mistake and not a fire, a theft or a failed disk, which is exactly what the home-server phase makes likely |
| Dumping to a cloud drive (iCloud, Dropbox) unencrypted | Puts the full household financial history, receipts included, in plaintext on someone else's storage |
| Trusting git plus "the data can be re-entered" | The ledger cannot be re-entered, which is the whole reason it is the asset |

## Consequences

We gain three things:

- The one irreplaceable thing in the system gets an encrypted copy somewhere
  else, every night.
- The monthly check turns the backup's existence into a fact instead of an
  assumption.
- The migration slice carries less risk, because moving home is a restore we
  have already practiced.

We accept four costs in return:

- Logical dumps recover to last night and not to the last minute, so the
  household can lose up to a day of captures and would have to re-enter them.
- The restic repository password and the secrets in the password manager become
  critical, because losing them loses the backups. We move that risk onto the
  password manager's own recovery story on purpose.
- Nightly dumps and monthly verification restores are moving parts that can fail
  without anyone noticing, which is why alerting into Telegram is part of this
  decision and not a nice-to-have.
- Storage costs a little every month, and dump duration grows with the audit
  log. If that ever matters, ADR 0008's pruning is the answer.

Little gets harder to change later. Logical dumps are the portable format, and
adding pgBackRest later only adds to this setup without invalidating the
existing repository.
