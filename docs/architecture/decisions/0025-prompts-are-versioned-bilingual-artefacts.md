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

# ADR 0025 - Prompts are versioned bilingual artefacts in this repository, gated by the golden set

## Context

A prompt decides what a capture becomes: which merchant, which category, which
account, and so whether the household's books gain a correct transaction or a
wrong one. That makes a prompt load-bearing logic, and it differs from ordinary
code in three ways.

It isn't deterministic: the same prompt returns different text on different days,
so we can only measure its quality and never assert it (ADR 0015). It is
bilingual, because members write in Russian and English (ADR 0017) and the
extraction has to be equally good in both, even though what it produces is
language-neutral slugs rather than words. And it is easy to edit in the wrong
place, because a prompt sits comfortably inside an n8n node, where no reviewer
sees it, no test covers it, and re-importing the workflow loses the edit.

ADR 0029 already puts prompts in the repository, but it doesn't say where they
live, what shape they take, or what we require of anyone who changes one.

## Decision

We keep each prompt as a file in this repository, versioned like code, and n8n
loads the file instead of carrying the text.

`prompts/<task>/` holds the system prompt, the output schema, and the few-shot
examples as separate plain-text and JSON files, never embedded in workflow JSON
or in a Code node, and the workflow refers to a prompt by task name and version.
Capture extraction, receipt reading, statement reading, and report answering each
get their own prompt and schema, because a single clever prompt for all four
means every change to one degrades the other three.

Every prompt declares its output schema, and we validate the response against
that schema before anything reaches the ledger. A response that fails validation
counts as a failed parse - an unparsed capture - and we never write part of it.
The schema carries the contract, and the prose carries the request.

One prompt handles both languages, with examples in each, because a member can
write in either and can mix numerals and words. It emits slugs, so its output
doesn't change with the input language. When a prompt has to produce text for a
person, such as a clarifying question, we pass it the member's language
explicitly and keep the wording in the message catalogue (ADR 0017). We also keep
the model out of the prompt: model choice stays configuration (ADR 0029), so a
prompt must not assume one provider's quirks.

### Changing a prompt is a gated act

Changing a prompt costs more than editing a file, because the diff tells a
reviewer almost nothing about the behaviour. Four steps close that gap.

We run the golden set before and after the change and record both scores in it
(ADR 0015); a prompt change with no recorded scores isn't reviewable and we don't
accept it. A regression in extracted numbers or chosen accounts blocks the
change, while wording differences don't. We bump the version and keep the old
one, because transactions record which prompt version interpreted them (ADR
0008), which is how we find and re-examine a run of bad extractions later.
Finally, we re-record the stubs in the same change: workflow tests replay
recorded model responses (ADR 0015), so a prompt change that leaves the stubs
alone leaves the tests asserting the behaviour of the old prompt.

## Alternatives

| Option | Why rejected |
|---|---|
| Prompts inside n8n nodes | Where they naturally end up, and they become invisible to review, impossible to diff, untestable, and lost on re-import |
| Prompts in the database, editable at runtime | Tempting for fast iteration, and it puts load-bearing logic outside version control and outside review - the exact failure ADR 0010 exists to prevent |
| One prompt for every task | Fewer files, and every task's quality becomes coupled to every other's. A change for receipts would silently move capture behaviour |
| Separate prompts per language | Doubles the maintenance and guarantees the two drift, so a household that mixes languages gets inconsistent books |
| Free-text output parsed with regular expressions | No schema, no validation boundary, and failures that look like successes |
| Trusting review without the golden set | Prompt changes are exactly the case where reading the diff tells you nothing about the behaviour |

## Consequences

Good:
- We can review, measure, and revert a prompt change the way we do any other
  change to logic that matters.
- We can trace a wrong extraction to the exact prompt version that produced it,
  which is how prompts actually improve.
- The schema boundary turns a bad response into a question to the member instead
  of a corrupt transaction.

Bad, and the price we accept:
- Changing a prompt is no longer a five-second edit in a UI. We want that
  friction, and we'll still resent it when something is obviously broken.
- The golden set costs money to run, so we run it deliberately, which means
  anyone can skip it and the gate holds only as a convention.
- Old prompt versions pile up as files nobody reads, and we keep them because
  they're what lets us explain history.
- One bilingual prompt is harder to tune than two, and a change that helps
  Russian can quietly hurt English. The golden set has to cover both languages,
  or it hides that failure.

What becomes harder to change later is the prompt-versioning scheme itself, once
transactions reference versions. We keep that reference a plain string rather
than a foreign key, which is what keeps a later change cheap.
