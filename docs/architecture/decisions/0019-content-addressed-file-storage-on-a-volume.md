---
id: 0019
title: Receipts and statements are stored as content-addressed files on a volume, not in the database
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0019 - Receipts and statements are stored as content-addressed files on a volume, not in the database

## Context

The product takes files: receipt photos, voice notes, and statement exports in
CAMT.053, CSV and PDF (ADR 0013). We have to keep them, because a capture or an
import must still be explainable months later (ADR 0008), and they are the most
sensitive data in the system: a statement is the household's complete financial
picture, and a receipt is a photograph of a life.

Two other decisions constrain this one. ADR 0009 takes nightly logical dumps of
the database, so anything stored in a table is dumped again in full every night.
ADR 0013 requires imports to be idempotent, which needs a reliable answer to
"have we seen this exact file before".

## Decision

Files live on a dedicated volume, content-addressed by SHA-256, and the database
holds the metadata and the hash.

- We derive the path from the hash (`ab/cd/abcdef…`), so storing the same file
  twice is free and spotting a re-upload is one lookup by hash. That gives us the idempotency key ADR 0013 asked for at no extra cost.
- The database row carries the hash, the original filename, the media type, the
  size, who uploaded it, when, and which capture or import it belongs to. The
  file itself never goes in a column.
- A periodic job re-hashes the stored files and reports a mismatch or a missing
  file to Telegram, because bit-rot in the only copy of a receipt would
  otherwise surface at the worst moment.
- The volume is in the backup set (ADR 0009), so restic encrypts it client-side
  before it leaves the host, and that requirement is what rules out any
  convenient third-party drive.
- We never serve files publicly. Access goes through the authenticated path, and
  guessing a hash reaches nothing.
- We keep files indefinitely by default, and we can deliberately prune the
  payloads of old model exchanges (ADR 0008) while keeping their metadata. We
  don't prune statement and receipt files, because they are the evidence.

## Alternatives

| Option | Why rejected |
|---|---|
| `bytea` columns in PostgreSQL | Transactional and simple, but then every nightly dump carries every receipt ever uploaded, so dump duration and backup size grow without bound for data that never changes - the worst fit for ADR 0009's logical dumps |
| PostgreSQL large objects | The same growth problem, plus a clumsier API and out-of-band deletion semantics |
| MinIO (self-hosted S3) | The "proper" answer, and out of proportion: a container, credentials and a bucket policy to gain S3 semantics we don't need, when restic already handles offsite storage and encryption. Revisit it only if something genuinely needs presigned URLs |
| A third-party object store or cloud drive | Puts household financial documents on someone else's storage, unencrypted from our side, against the privacy principle |
| Filenames as given, in a flat directory | Collides, gives no idempotency, and puts user-supplied names in a filesystem path |
| Keep nothing - parse and discard | The cheapest option, and it takes away any way to explain a wrong parse or re-import an upgraded statement. The audit design needs the original to still be there |

## Consequences

Good:
- Nightly dumps stay small and fast, because they carry metadata instead of
  megabytes.
- We detect duplicate uploads and re-imports exactly, by hash.
- Backups cover the files, encrypted, with no extra machinery.
- The re-hashing job finds corruption while there is still time to restore the
  file, so nobody discovers it at the moment they need it.

Bad, and the price we accept:
- The files and the database can disagree, because a restore that brings back
  one but not the other leaves references pointing at nothing. The restore
  verification (ADR 0009) therefore checks both.
- Deleting a file is no longer transactional, so a row can be gone while the
  bytes remain. We handle that by treating orphan bytes as garbage for a
  collection job to sweep up.
- The application needs a little code to store and read files. Content
  addressing keeps that code small, but it isn't free.

Moving to an object store later stays cheap. Content-addressed files copy across
under the same keys, so only the storage path in the application changes, if
that ever becomes worth doing.
