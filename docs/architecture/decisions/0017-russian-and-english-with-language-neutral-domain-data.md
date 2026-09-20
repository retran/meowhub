---
id: 0017
title: Russian and English, with domain data stored language-neutral
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amended-by: [0031, 0046]
---

# ADR 0017 - Russian and English, with domain data stored language-neutral

## Context

The household speaks Russian and English. It lives in the Netherlands, so part
of the data is Dutch - statement descriptors, merchant names, bank field text -
even though nobody wants a Dutch interface.

We have to decide this before the schema exists. Category and account names are
the kind of thing somebody types into a table as free text, and then it's wrong
for years: renaming a category once history is posted against it means
migrating real data, and translating one is impossible when the name is also the
identifier.

## Decision

- The system speaks Russian and English. Each member has a language preference,
  and the bot replies, the digests arrive and the app renders in that language.
  Nothing faces the member in Dutch.
- We store domain data language-neutral. Categories, account types and every
  other enumerated domain concept are **stable slugs**, and display names live in
  a translations table keyed by slug and language, so a report groups by slug and
  renders by language.
- Merchant names are data and we never translate them. A merchant is whatever
  the world calls it, such as `Albert Heijn`, and its aliases (ADR 0004) absorb
  the spelling variants, including the Dutch statement descriptors.
- Parsing handles Dutch input whatever the interface language is, because
  statements and receipts are Dutch. The comma decimal separator is the ordinary
  case here and not an edge case.
- Both languages are first-class in capture. A member can write "кофе 350" or
  "coffee 350"; the extraction is language-agnostic, and the category resolves to
  the same slug either way.
- The repository stays English - specs, ADRs, code, comments, commit messages,
  table and column names - and we translate only the strings a member sees.
- Translations are code: the message catalogue lives in this repository and ships
  with the app and the workflows (ADR 0010), and nobody edits it in a running UI.

## Alternatives

| Option | Why rejected |
|---|---|
| One interface language | The simplest option, and we refused it because the household genuinely uses both, and a shared ledger nobody wants to read is the failure this product exists to avoid |
| Category names as free text in the member's language | The trap this ADR exists to avoid. Reports fragment by spelling, translation becomes impossible, and a rename turns into a data migration |
| Full internationalisation framework with locale negotiation, plurals, dates | Out of proportion for two languages and three people. A flat catalogue plus a per-member preference is enough, and we can add machinery when something needs it |
| Include Dutch in the interface | Nobody asked for it. Dutch matters on the way in, not on the way out |
| Let the model translate on the fly | Gives financial reports non-deterministic labels, and charges per render |

## Consequences

**Good:**
- We can rename or retranslate a category or account name without touching a
  single posting.
- Reports stay comparable across languages, because they group by slug.
- Both members read the books in their own language, which is what makes them
  read the books at all.

**Bad, and the price we accept:**
- Every new category needs two display names, and a missing translation has to
  fall back visibly instead of quietly showing a slug.
- We keep two languages in step across prompts, digests and the app, and prompts
  are the awkward part, because a prompt is also where a language leaks
  subtly.
- Slugs in the database mean that anyone reading raw tables sees `groceries`
  instead of a friendly name. We accept that, because the app and the bot are
  the interfaces.

**What becomes harder to change later:** adding a third language is easy, while
retrofitting slugs after free-text names have accumulated would not be, which is
why we decide it now.
