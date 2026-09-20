---
description: Create a new feature spec from a description
argument-hint: <feature description>
---

Load the `technical-english` skill before drafting: a spec is prose, and this one is read by whoever builds the feature.

Create a new spec for: $ARGUMENTS

Steps:

1. Pick the next free number: list `specs/` and take max+1, zero-padded to
   `NNNN`. If there are no specs yet, use `0001`.
2. Choose a short kebab-case slug describing the feature. Directory:
   `specs/NNNN-slug/`.
3. Copy `specs/_templates/spec.md` and `specs/_templates/notes.md` into it.
4. Fill in `spec.md`:
   - front matter: id, title, status `draft`, created/updated set to today;
   - every section substantively, grounded in the user's description,
     `docs/product/vision.md` and what is actually in the repository.
5. Hold the line: **a spec describes behaviour, not implementation.** No node
   names, service names or table schemas — those go to `plan.md`.
6. Phrase requirements (`R*`) and acceptance criteria (`A*`) so that a test
   follows directly from each one.
7. Do not invent anything you do not know. Put it in "Open questions" and
   classify it by **what it blocks**: `design` (the schema or behaviour cannot be
   settled without it — this alone holds the plan), `build` (a real file, a
   credential, a verified assumption), `deploy` (a provider, a domain, a
   purchase), `data` (a household fact needed to use the system, not to build
   it), or `nothing` (a preference with a default). Do not mark a deployment
   question as blocking the plan.
8. If the feature needs a project-level decision (platform, storage, protocol),
   flag it as an ADR required rather than deciding it in the spec.
9. Fill in the **Ergonomic cost** section properly — all four questions from
   `docs/standards/ergonomics.md`. A slice that cannot say what happens if nobody
   touches it for a month is not ready. "No new work for anyone" is a valid
   answer only if it is true.
10. Check the spec's vocabulary against `docs/product/glossary.md`. Use the terms
    that are there; if the feature introduces a genuinely new concept, say so —
    the glossary needs a row.

Write everything in English.

Finish by showing the user:
- the path to the new spec;
- a short restatement of the requirements and scope;
- the open questions, blocking ones first, and ask them to answer.

Do not write `plan.md` and do not write code.
