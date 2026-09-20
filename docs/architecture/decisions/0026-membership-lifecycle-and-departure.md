---
id: 0026
title: Membership changes are a designed event, and a departure does not rewrite the books
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0026 - Membership changes are a designed event, and a departure does not rewrite the books

## Context

The household is three people today, and a system that keeps a decade of
financial records will outlive that arrangement. The daughter grows up, moves
out, and might want her own data; a household can gain a member; and two adults
can separate, which is the case nobody designs for and everybody eventually
needs.

ADR 0030 makes a member a row keyed by a Telegram user id, and every transaction
carries its submitter, which can't be null. A departure therefore touches the
ledger's integrity directly: deleting a member would orphan years of postings,
and the audit log (ADR 0008) is append-only by design, so we must not rewrite it
to fit a life event.

One question here isn't technical at all. The books belong to the household, and
the entries a person made are in some sense about that person, so a household
member is right to distrust a system that can't answer "give me my data".

## Decision

### A member is deactivated, never deleted

Departure sets the member inactive, with a date. We keep the row, so every
transaction keeps a valid submitter and every historical report keeps its
attribution.

An inactive member loses access immediately: we remove them from the Telegram
allow-list, disable their identity-provider account, and revoke their passkeys.
We withdraw access and leave attribution alone, because the two answer different
questions.

We don't rewrite the books. No transaction is re-attributed, deleted, or
anonymised, because a household's financial history records what happened, and
reports covering past periods keep showing who submitted what.

When the departing member was an admin (ADR 0024), we rotate the secrets they
held - bot token, API keys, database credentials - and re-issue the shared vault
without them. That is the one step we never defer, because until it's done the
former admin can still reach everything.

### Data on request, as an export

Any member can ask for their own data and gets an export: the transactions they
submitted, the captures they sent, and the files they uploaded, in a plain,
portable form - CSV plus the original files.

The export is a copy, not a removal. The household's ledger keeps its entries,
and the member takes the export with them.

An admin produces the export by a documented procedure, so nobody has to write an
ad-hoc query under emotional pressure.

### A household that splits is a fork, not a filter

If the two adults separate, each takes a copy of the whole installation. The same
restore procedure that moves the system to the home server (spec 0011) builds a
second, independent household from a backup, and each side then deletes what they
don't want in their own copy.

We decided against building a "split the ledger" feature, because software can't
divide a shared ledger correctly: joint accounts, a mortgage, and a shared card
don't separate into two truthful halves, so the feature would hand each side a
confident set of books that is subtly wrong.

### What is not in scope

Two things a reader might expect here are deliberately absent.

We tie no retention policy to departure, because ADR 0008 already decided to keep
records indefinitely. We also build no right-to-erasure machinery: this is a
private household system rather than a service with data subjects, so legal
ceremony would add process without adding protection.

## Alternatives

| Option | Why rejected |
|---|---|
| Delete the member row | Orphans every posting they submitted, breaks attribution in historical reports, and would require rewriting an append-only audit log |
| Anonymise their history | Destroys information the household may need - "who bought this" is sometimes the question - and the anonymisation cannot be undone if it was a mistake |
| Keep access after departure, informally | Leaves a former member with the household's complete financial picture because nobody got round to a checklist. The worst outcome, and the most likely one without a decision |
| A built-in ledger split | Software cannot divide a joint mortgage into two true halves. It would produce two confident, wrong sets of books at the worst possible time |
| Transfer the daughter's history to a new installation of her own | A kind idea that means deleting it here, which breaks the household's own past reports. An export she keeps is the same benefit without the loss |
| Formal data-subject processes | Ceremony borrowed from a context that does not apply to a three-person household |

## Consequences

Good:
- Historical reports stay correct forever, because we never rewrite attribution.
- A departure has a checklist, so revoking access and rotating secrets doesn't
  depend on anyone's composure at the time.
- "Give me my data" has a real answer, which is part of why members trust the
  system enough to feed it.

Bad, and the price we accept:
- A former member's name and spending stay in the household's books indefinitely.
  We chose accurate history over that discomfort, and one day it will feel wrong
  to someone.
- Splitting as a fork is honest and unsatisfying, because it leaves two copies of
  everything and each side has to prune its own by hand.
- We write the export and run it rarely, which is the kind of code that rots, so
  a test exercises it rather than only a procedure.

What becomes harder to change later is real erasure: adopting it would mean
confronting the append-only audit log, which is load-bearing. Keeping
deactivation and export as the only two operations is what stops us ever needing
to.
