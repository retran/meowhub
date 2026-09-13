---
id: 0019
title: Receipts and statements are stored as content-addressed files on a volume, not in the database
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0019 — Receipts and statements are stored as content-addressed files on a volume, not in the database

## Context

The product takes files: receipt photos, voice notes, and statement exports —
CAMT.053, CSV and PDF (ADR 0013). They have to be kept, because a capture or an
import must remain explainable months later (ADR 0008), and they are the most
sensitive data in the system: a statement is the household's complete financial
picture, a receipt is a photograph of a life.

The decision interacts with two others. ADR 0009 takes **nightly logical dumps**
of the database, so anything stored in a table is re-dumped in full every night.
And ADR 0013 requires imports to be **idempotent**, which needs a reliable answer
to "have we seen this exact file before".

## Decision

**Files live on a dedicated volume, content-addressed by SHA-256; the database
holds the metadata and the hash.**

- **The path is derived from the hash** (`ab/cd/abcdef…`), so storing the same
  file twice is free and detecting a re-upload is a lookup, not a heuristic. This
  is the idempotency key ADR 0013 asked for, obtained for nothing.
- **The database row carries** the hash, the original filename, the media type,
  the size, who uploaded it, when, and which capture or import it belongs to. The
  file itself is never in a column.
- **Integrity is checkable**: a periodic job re-hashes stored files and reports a
  mismatch or a missing file to Telegram, because silent bit-rot in the one copy
  of a receipt would otherwise be found at the worst moment.
- **The volume is in the backup set** (ADR 0009) and therefore encrypted
  client-side before leaving the host — which is the requirement that rules out
  any convenient third-party drive.
- **Files are never served publicly.** Access goes through the authenticated
  path; nothing is reachable by guessing a hash.
- **Retention: kept indefinitely by default**, with the deliberate option to prune
  the *payloads* of old model exchanges (ADR 0008) while keeping the metadata.
  Statement and receipt files themselves are not pruned — they are the evidence.

## Alternatives

| Option | Why rejected |
|---|---|
| `bytea` columns in PostgreSQL | Transactional and simple, and it makes every nightly dump carry every receipt ever uploaded. Dump duration and backup size grow without bound for data that never changes — the worst fit for ADR 0009's logical dumps |
| PostgreSQL large objects | Same growth problem, plus a clumsier API and out-of-band deletion semantics |
| MinIO (self-hosted S3) | The "proper" answer, and disproportionate: a container, credentials and a bucket policy to gain S3 semantics we do not need, when restic already handles offsite and encryption. Revisit only if something genuinely needs presigned URLs |
| A third-party object store or cloud drive | Household financial documents on someone else's storage, unencrypted from our side. Against the privacy principle |
| Filenames as given, in a flat directory | Collisions, no idempotency, and user-supplied names in a filesystem path |
| Keep nothing — parse and discard | Cheapest, and it removes the ability to explain a wrong parse or re-import an upgraded statement. The audit design depends on the original being there |

## Consequences

**Good:**
- Nightly dumps stay small and fast, because they contain metadata rather than
  megabytes.
- Duplicate uploads and re-imports are detected exactly, by hash.
- Backups cover the files, encrypted, with no extra machinery.
- Corruption is detected by a job rather than by a person needing the file.

**Bad, and the price we accept:**
- **The files and the database can disagree.** A restore that brings back one but
  not the other leaves dangling references — so the restore verification
  (ADR 0009) must check both, and does.
- Deleting a file is no longer transactional: a row can be gone while bytes
  remain, which is handled by treating orphan bytes as garbage to collect rather
  than as an error.
- The application needs a small amount of code for storing and reading files
  — content addressing means it is little, but it is not nothing.

**What becomes harder to change later:** almost nothing. Content-addressed files
move to an object store by copying them under the same keys, if that ever becomes
worth doing.
