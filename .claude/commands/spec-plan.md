---
description: Write the implementation plan for an approved spec
argument-hint: <NNNN — spec number>
---

Write the implementation plan for spec $ARGUMENTS.

1. Find `specs/$ARGUMENTS-*/` and read `spec.md` in full, plus `notes.md` if present.
2. Check readiness:
   - status must be `approved` (if `review`, warn and continue only if the user
     asks);
   - no `design` question may still be open. Open `deploy` and `data` questions
     do not hold the plan back — development runs on the seeded household.
   If either fails, **stop** and say what is missing.
3. Read `docs/architecture/overview.md` and the accepted ADRs in
   `docs/architecture/decisions/` so the plan does not contradict decisions
   already made. If it must contradict one, that is grounds for a new ADR —
   say so explicitly.
4. Study the relevant existing workflows and code before proposing structure.
   Build on the patterns already in the repository, not on abstractly better ones.
5. Copy `specs/_templates/plan.md` into the spec directory and fill it in.
   Mandatory:
   - at least one genuinely considered alternative with the reason for rejection;
   - the acceptance-criteria table covering every `A*` in the spec;
   - migration and compatibility, even if the answer is "purely additive";
   - for every number the feature shows anywhere, **the SQL view it comes from**,
     named in `docs/architecture/data-model.md` — and if it is not in that
     catalogue, the plan adds it there rather than inventing a name.
     Nothing computes totals outside the database (ADRs 0004, 0011, 0014), so a
     figure with no named view is not yet available;
   - for every acceptance criterion, **which test will close it** and at which
     level, per ADR 0015: pgTAP for anything in the database, including row-level
     security tested by impersonation; parser tests over committed fixtures;
     `n8n execute` with the model gateway stubbed for workflows; Playwright at
     phone viewport for screens.
6. Move anything that outlives the feature into "ADRs required" and offer to
   draft the ADR from `specs/_templates/adr.md`.
7. If the feature has any screen, follow `docs/standards/ui-design-process.md`:
   name the question and who asks it, name the view before the layout, and
   enumerate every state — including empty-because-new. Build from the design
   system in ADR 0022; a new component or token needs a sentence of justification
   here, not in a commit message.

Write everything in English.

Show the user the approach, the chosen alternative and the main risks.
No tasks and no code in this command.
