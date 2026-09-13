---
id: 0026
title: Membership changes are a designed event, and a departure does not rewrite the books
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0026 — Membership changes are a designed event, and a departure does not rewrite the books

## Context

The household is three people today. Over the life of a system that keeps a
decade of financial records, that will change: the daughter grows up, moves out
and may want her own data; a household can gain a member; and two adults can
separate, which is the case nobody designs for and everybody eventually needs.

ADR 0030 makes a member a row keyed by a Telegram user id, and every transaction
carries its submitter, which cannot be null. So a departure touches the ledger's
integrity directly: deleting a member would orphan years of postings, and the
audit log (ADR 0008) is append-only by design and must not be rewritten to
accommodate a life event.

There is also a question that is not technical. The books belong to the
household; the entries a person made are, in some sense, about them. A system
that cannot answer "give me my data" is a system people are right not to trust.

## Decision

### A member is deactivated, never deleted

- Departure sets the member inactive, with a date. The row stays, so every
  transaction keeps a valid submitter and every historical report keeps its
  attribution.
- **An inactive member loses access immediately**: removed from the Telegram
  allow-list, their identity-provider account disabled, their passkeys revoked.
  Access and attribution are separate things, and only access is withdrawn.
- **The books are not rewritten.** No transaction is re-attributed, deleted or
  anonymised, because a household's financial history is a record of what
  happened. Reports covering past periods continue to show who submitted what.
- **Secrets are rotated** when a departing member was an admin (ADR 0024) — bot
  token, API keys, database credentials — and the shared vault is re-issued
  without them. This is the one step that must not be deferred.

### Data on request, as an export

- **Any member may ask for their own data**, and receives an export: the
  transactions they submitted, the captures they sent, and the files they
  uploaded, in a plain, portable form — CSV plus the original files.
- **This is a copy, not a removal.** The household's ledger keeps its entries;
  the export is theirs to take.
- **The export is produced by an admin** and is a documented operation, not an
  ad-hoc query written under emotional pressure.

### A household that splits is a fork, not a filter

If the two adults separate, the honest answer is that **each takes a copy of the
whole installation**: the same restore procedure that moves the system to the home
server (spec 0011) produces a second, independent household from a backup, and
each side then deletes what they do not want in their own copy.

We deliberately do **not** build a "split the ledger" feature. A shared ledger
cannot be divided correctly by software — joint accounts, a mortgage and a shared
card do not separate into two truthful halves — and attempting it would produce
two sets of books that are each subtly wrong.

### What is not in scope

- No retention policy tied to departure: records are kept indefinitely, as
  ADR 0008 already decided.
- No right-to-erasure machinery. This is a private household system, not a
  service with data subjects, and inventing legal ceremony would add process
  without adding protection.

## Alternatives

| Option | Why rejected |
|---|---|
| Delete the member row | Orphans every posting they submitted, breaks attribution in historical reports, and would require rewriting an append-only audit log |
| Anonymise their history | Destroys information the household may need — "who bought this" is sometimes the question — and the anonymisation cannot be undone if it was a mistake |
| Keep access after departure, informally | Leaves a former member with the household's complete financial picture because nobody got round to a checklist. The worst outcome, and the most likely one without a decision |
| A built-in ledger split | Software cannot divide a joint mortgage into two true halves. It would produce two confident, wrong sets of books at the worst possible time |
| Transfer the daughter's history to a new installation of her own | A kind idea that means deleting it here, which breaks the household's own past reports. An export she keeps is the same benefit without the loss |
| Formal data-subject processes | Ceremony borrowed from a context that does not apply to a three-person household |

## Consequences

**Good:**
- Historical reports stay correct forever, because attribution is never rewritten.
- A departure has a checklist, so the step that actually matters — revoking
  access and rotating secrets — does not depend on anyone's composure at the time.
- "Give me my data" has a real answer, which is part of why members trust the
  system enough to feed it.

**Bad, and the price we accept:**
- A former member's name and spending stay in the household's books indefinitely.
  That is a deliberate choice in favour of accurate history, and it will feel
  wrong to someone one day.
- The split-as-fork answer is honest and unsatisfying: two copies of everything,
  each needing manual pruning.
- The export is code we write and rarely run, which is the kind of code that rots
  — so it is exercised by a test, not only by a procedure.

**What becomes harder to change later:** adopting real erasure would mean
confronting the append-only audit log, which is load-bearing. Keeping deactivation
and export as the only two operations is what avoids ever needing to.
