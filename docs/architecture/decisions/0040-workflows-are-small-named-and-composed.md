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

# ADR 0040 - Workflows are small, named by what they do, and composed rather than branched

## Context

ADR 0001 chose n8n and told us to keep nodes thin, with the logic in SQL. It said
nothing about how many workflows we should have, what we call them, how they call
each other, or what happens when one fails, and those conventions decide whether
a year from now we have four readable flows or one canvas nobody will open.

The pressure runs one way. Every new capability is easiest to add as another
branch in the workflow that already receives the message, because the data is
already there. Follow that for a year and we end up with a single workflow of
forty nodes, a diff no reviewer can read (ADR 0010), and no way to test one path
without running all of them.

## Decision

The owner set eight conventions for every workflow in this system.

- One workflow does one job and is named for that job in the imperative:
  `capture-text`, `capture-photo`, `import-statement`, `send-weekly-digest`,
  `verify-restore`, `detect-drift`. A reader knows what it does before opening
  it.
- Each external trigger has one entry point, and that entry point only
  normalises and dispatches. The Telegram trigger resolves the member from the
  channel binding (ADR 0030), normalises the message (ADR 0027), loads any open
  conversation (ADR 0038), and calls the workflow that handles it, with no
  product logic of its own.
- Shared steps are sub-workflows instead of copies: resolving a member, calling
  a tool, recording a failure, and replying in the member's language. Two copies
  of a step are how two paths start behaving differently.
- Branching handles failure, and it doesn't select features. A conditional that
  chooses between two kinds of work means the work belongs in two workflows.
- Every workflow has the same single failure path: record the failure against
  the capture or the import, tell the member something true, and, for scheduled
  work, don't push the heartbeat (ADR 0020). A workflow that can fail silently
  is incomplete.
- Scheduled work always lives in a different workflow from conversational work,
  so a capture can't delay a digest and a slow model can't delay a backup.
- No workflow computes a figure. Every number comes from the view catalogue
  (`data-model.md`), and a workflow that does arithmetic on money is a defect.
- No workflow stores anything. Configuration lives in the environment
  (ADR 0034), state lives in the database (ADR 0038), and prompts and tools live
  in files (ADRs 0025, 0039), so a workflow is only wiring.
- Every workflow is exported to this repository, and the export is part of being
  done (ADR 0010).

## Alternatives

| Option | Why rejected |
|---|---|
| One workflow per trigger, branching inside | The way things drift by default, because the data is already there; it ends as one canvas no reviewer can read, with no path testable on its own |
| Workflows named after the feature or the slice | `slice-0003` will mean nothing in a year, and a workflow outlives the slice that introduced it |
| Duplicating shared steps for independence | Avoids a dependency and guarantees divergence, because two copies of "reply in the member's language" won't stay the same |
| Putting normalisation in each handler | Every handler would then know about Telegram, so changing messenger would touch all of them instead of one, which is what ADR 0027 exists to prevent |
| No convention; decide per workflow | A convention decided case by case isn't a convention, and this is the one part of the system where a diff can't review itself |

## Consequences

Good:
- Each workflow can be read, tested, and replaced on its own, which is what
  makes ADR 0015's end-to-end tests feasible.
- Changing the messenger, the model gateway, or a tool touches one place.
- Failure handling is uniform, so "did it fail silently" has one answer.
- The export diff stays small enough to mean something.

Bad, and the price we accept:
- We have more workflows to name, export, and keep tidy, and a sub-workflow call
  costs more indirection than a branch, which hurts more in a visual tool than
  in code.
- Reviewers have to enforce the convention, because nothing in n8n stops anyone
  from adding a fortieth node.
- Splitting conversational work from scheduled work leaves two places that send
  a message, and they share a sub-workflow instead of being one flow.

What becomes harder to change later is the entry point's contract, once every
handler depends on the shape it dispatches. That shape is the normalisation
ADR 0027 already required, so we maintain one contract and not two.
