---
id: 0040
title: Workflows are small, named by what they do, and composed rather than branched
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amended-by: [0046]
---

# ADR 0040 — Workflows are small, named by what they do, and composed rather than branched

## Context

ADR 0001 chose n8n and said to keep nodes thin, with logic in SQL. It said nothing
about how many workflows there should be, what they are called, how they call each
other, or what happens when one fails — and those conventions decide whether a
year from now this is four readable flows or one canvas nobody will open.

The pressure is specific and one-directional. Every new capability is easiest to
add as another branch in the workflow that already receives the message, because
that is where the data already is. Follow that for a year and there is a single
workflow with forty nodes, an unreviewable diff (ADR 0010), and no way to test one
path without running all of them.

## Decision

- **One workflow per job, named for the job** in the imperative:
  `capture-text`, `capture-photo`, `import-statement`, `send-weekly-digest`,
  `verify-restore`, `detect-drift`. A reader knows what it does before opening it.
- **One entry point per external trigger**, and it does nothing but normalise and
  dispatch. The Telegram trigger resolves the member from the channel binding
  (ADR 0030), normalises the message (ADR 0027), loads any open conversation
  (ADR 0038) and calls the workflow that handles it. It contains no product logic.
- **Shared steps are sub-workflows, not copies**: resolving a member, calling a
  tool, recording a failure, sending a reply in the member's language. A second
  copy of a step is how two paths start behaving differently.
- **Branching is for failure, not for features.** A conditional that selects
  between two *kinds of work* is a sign the work belongs in two workflows.
- **Every workflow has one failure path**, and it is the same one: record the
  failure against the capture or the import, tell the member something true, and —
  for scheduled work — do not push the heartbeat (ADR 0020). A workflow that can
  fail silently is incomplete.
- **Scheduled work is separate from conversational work**, always, so a digest
  cannot be delayed by a capture and a slow model cannot delay a backup.
- **No workflow computes a figure.** Everything numeric comes from the view
  catalogue (`data-model.md`); a workflow that does arithmetic on money is a
  defect.
- **Nothing is stored in a workflow.** Configuration is environment (ADR 0034),
  state is the database (ADR 0038), prompts and tools are files (ADRs 0025, 0039).
  A workflow is only wiring.
- **Every workflow is exported to this repository** and its export is part of
  being done (ADR 0010).

## Alternatives

| Option | Why rejected |
|---|---|
| One workflow per trigger, branching inside | The default drift. It is where the data already is, and it ends as one unreviewable canvas with no path testable alone |
| Workflows named after the feature or the slice | `slice-0003` means nothing in a year, and a workflow outlives the slice that introduced it |
| Duplicating shared steps for independence | Avoids a dependency and guarantees divergence: two copies of "reply in the member's language" will not stay the same |
| Putting normalisation in each handler | Every handler then knows about Telegram, and changing messenger touches all of them rather than one (ADR 0027's whole point) |
| No convention; decide per workflow | Conventions that are decided per case are not conventions, and this is the one part of the system where a diff cannot review itself |

## Consequences

**Good:**
- A workflow can be read, tested and replaced on its own, which is what makes
  ADR 0015's end-to-end tests feasible.
- Changing the messenger, the model gateway or a tool touches one place.
- Failure handling is uniform, so "did it fail silently" has one answer.
- The export diff stays small enough to mean something.

**Bad, and the price we accept:**
- More workflows to name, export and keep tidy, and sub-workflow calls are more
  indirection than a branch would be — which is worse in a visual tool than in
  code.
- The convention has to be enforced by review, because nothing in n8n prevents a
  fortieth node.
- Splitting conversational from scheduled work means two places handle "send a
  message", and they share a sub-workflow rather than being one flow.

**What becomes harder to change later:** the entry point's contract, once every
handler depends on the shape it dispatches. That shape is the same normalisation
ADR 0027 already required, so it is one thing rather than two.
