---
id: 0017
title: Russian and English, with domain data stored language-neutral
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amended-by: [0031]
---

# ADR 0017 — Russian and English, with domain data stored language-neutral

## Context

The household speaks Russian and English. It lives in the Netherlands, so the
*data* is partly Dutch — statement descriptors, merchant names, bank field text —
even though nobody wants a Dutch interface.

This has to be decided before the schema exists. Category and account names are
the kind of thing that gets typed into a table as free text and is then wrong for
years: renaming a category once history is posted against it is a migration over
real data, and translating one is impossible if the name *is* the identifier.

## Decision

- **The system speaks Russian and English.** Each member has a language
  preference; the bot replies, the digests arrive and the app renders in that
  language. Nothing is Dutch-facing.
- **Domain data is stored language-neutral.** Categories, account types and every
  other enumerated domain concept are **stable slugs**, with display names held in
  a translations table keyed by slug and language. A report groups by slug and
  renders by language.
- **Merchant names are data, not translated.** A merchant is whatever it is called
  in the world — `Albert Heijn` — and is never translated. Its aliases (ADR 0004)
  absorb the spelling variants, including the Dutch statement descriptors.
- **Parsing must handle Dutch input regardless of interface language**, because
  statements and receipts are Dutch. The comma decimal separator is the ordinary
  case, not an edge case.
- **Both languages are first-class in capture.** A member may write "кофе 350" or
  "coffee 350"; the extraction is language-agnostic and the category resolves to
  the same slug either way.
- **The repository stays English** — specs, ADRs, code, comments, commit
  messages, table and column names. Only user-facing strings are translated.
- **Translations are code**: the message catalogue lives in this repository and
  ships with the app and the workflows (ADR 0010), never edited in a running UI.

## Alternatives

| Option | Why rejected |
|---|---|
| One interface language | Simplest, and refused: the household genuinely uses both, and a shared ledger nobody wants to read is the failure mode this product exists to avoid |
| Category names as free text in the member's language | The trap this ADR exists to avoid. Reports fragment by spelling, translation becomes impossible, and a rename becomes a data migration |
| Full internationalisation framework with locale negotiation, plurals, dates | Disproportionate for two languages and three people. A flat catalogue plus per-member preference is enough; add machinery when something actually needs it |
| Include Dutch in the interface | Nobody asked. Dutch matters on the way in, not on the way out |
| Let the model translate on the fly | Non-deterministic labels in financial reports, paid per render |

## Consequences

**Good:**
- Category and account names can be renamed or retranslated without touching a
  single posting.
- Reports are comparable across languages because they group by slug.
- Both members read the books in their own language, which is what gets them used
  at all.

**Bad, and the price we accept:**
- Every new category needs two display names, and a missing translation must fall
  back visibly rather than silently showing a slug.
- Two languages to keep in step in prompts, digests and the app — and prompts are
  the awkward part, since a prompt is also the place a language subtly leaks.
- Slugs in the database mean a human reading raw tables sees `groceries`, not a
  friendly name. Acceptable: the app and the bot are the interfaces.

**What becomes harder to change later:** adding a third language is easy;
retrofitting slugs after free-text names have accumulated would not be — which is
exactly why this is decided now.
