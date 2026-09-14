---
id: 0025
title: Prompts are versioned bilingual artefacts in this repository, gated by the golden set
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amended-by: [0046]
---

# ADR 0025 — Prompts are versioned bilingual artefacts in this repository, gated by the golden set

## Context

A prompt decides what a capture becomes: which merchant, which category, which
account, and whether the household's books gain a correct transaction or a wrong
one. It is therefore load-bearing logic, and it has three properties that ordinary
code does not:

- **It is not deterministic.** The same prompt returns different text on different
  days, and its quality can only be measured, not asserted (ADR 0015).
- **It is bilingual.** Members write in Russian and English (ADR 0017), and the
  extraction must be equally good in both — while the *output* it produces is
  language-neutral slugs, not words.
- **It is easy to edit in the wrong place.** A prompt lives naturally inside an
  n8n node, where it is invisible to review, untested, and lost when the workflow
  is re-imported.

ADR 0029 says prompts live in the repository. Nothing yet says where, in what
shape, or what changing one requires.

## Decision

**A prompt is a file in this repository, versioned like code**, and n8n loads it
rather than containing it.

- **Location and shape:** `prompts/<task>/` holds the system prompt, the output
  schema, and the few-shot examples as separate files — plain text and JSON, never
  embedded in workflow JSON or in a Code node. The workflow references a prompt by
  task name and version.
- **One task, one prompt.** Capture extraction, receipt reading, statement
  reading and report answering are separate prompts with separate schemas. A
  single clever prompt for everything is how all four get worse together.
- **Every prompt declares its output schema**, and the response is validated
  against it before anything reaches the ledger. A response that does not
  validate is a failed parse — an unparsed capture — never a partial write. The
  schema is the contract; the prose is the request.
- **Bilingual by construction, not by translation.** One prompt handles both
  languages, with examples in each, because a member may write either and may mix
  numerals and words. It emits slugs, so its output does not vary with the input
  language. Where a prompt must produce text for a person — a clarifying question
  — it is given the member's language explicitly and the wording lives in the
  message catalogue (ADR 0017), not in the prompt.
- **The model is not named in the prompt.** Model choice stays configuration
  (ADR 0029), so a prompt must not assume a provider's quirks.

### Changing a prompt is a gated act

- **The golden set runs before and after**, and the scores are recorded in the
  change (ADR 0015). A prompt change with no recorded scores is not reviewable
  and is not accepted.
- **A regression in extracted numbers or chosen accounts blocks the change.**
  Wording differences do not.
- **The version is bumped and the old version kept**, because transactions record
  which prompt version interpreted them (ADR 0008) — so a run of bad extractions
  can be found and re-examined later.
- **Recorded stubs are refreshed deliberately.** Workflow tests replay recorded
  model responses (ADR 0015); when a prompt changes, its stubs are re-recorded in
  the same change, or the tests quietly assert the behaviour of an old prompt.

## Alternatives

| Option | Why rejected |
|---|---|
| Prompts inside n8n nodes | Where they naturally end up, and they become invisible to review, impossible to diff, untestable, and lost on re-import |
| Prompts in the database, editable at runtime | Tempting for fast iteration, and it puts load-bearing logic outside version control and outside review — the exact failure ADR 0010 exists to prevent |
| One prompt for every task | Fewer files, and every task's quality becomes coupled to every other's. A change for receipts would silently move capture behaviour |
| Separate prompts per language | Doubles the maintenance and guarantees the two drift, so a household that mixes languages gets inconsistent books |
| Free-text output parsed with regular expressions | No schema, no validation boundary, and failures that look like successes |
| Trusting review without the golden set | Prompt changes are exactly the case where reading the diff tells you nothing about the behaviour |

## Consequences

**Good:**
- Prompt changes are reviewable, measurable and revertible, like any other change
  to logic that matters.
- A wrong extraction can be traced to the exact prompt version that produced it,
  which is how prompts actually improve.
- The schema boundary means a bad response degrades to a question rather than to
  a corrupt transaction.

**Bad, and the price we accept:**
- Changing a prompt is no longer a five-second edit in a UI. That friction is the
  feature, and it will be resented when something is obviously broken.
- The golden set costs money to run, so it is run deliberately — which means
  someone can skip it, and the gate is a convention rather than a mechanism.
- Keeping old prompt versions accumulates files nobody reads, in exchange for
  being able to explain history.
- One bilingual prompt is harder to tune than two, and a change that helps
  Russian can quietly hurt English. The golden set must cover both, or it hides
  exactly this.

**What becomes harder to change later:** the prompt-versioning scheme itself, once
transactions reference versions. Keeping the reference a plain string rather than
a foreign key is what keeps that cheap.
