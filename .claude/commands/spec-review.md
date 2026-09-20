---
description: Verify an implementation against its spec and acceptance criteria
argument-hint: <NNNN — spec number>
---

Load the `technical-english` skill first: the review you write is prose, and so is anything you fix in the spec.

Verify the implementation of spec $ARGUMENTS.

1. Read `spec.md`, `plan.md` and `tasks.md`.
2. Walk **every** acceptance criterion (`A*`) and requirement (`R*`) and find
   the evidence that it holds. Per ADR 0015, **evidence is a named passing test** —
   file and test name — or, only where automation is genuinely impossible, a
   recorded manual run with its date. Prose is not evidence, and a plausible
   implementation is not evidence. Missing evidence means "not met", not
   "probably met".
   Run the suite; for screens, run the Playwright journeys yourself rather than
   reasoning about them.
3. Check the edge-case table from the spec: is each case handled.
4. Check deviations from the plan: what was done differently, and whether the
   deviation log records it.
5. Run the project's tests and checks if any exist. Quote the actual output.
   A failure is reported as a failure.
6. Call out anything implemented beyond the spec (scope creep) — that is a
   discrepancy too.
7. Check the spec's **Ergonomic cost** answers against what was actually built:
   a queue with no drain, a new recurring chore that is not in the table in
   `docs/standards/ergonomics.md`, or a new interruption is a finding, not a
   detail.

Produce a table of `requirement/criterion → status → evidence` and an honest
verdict:
- all closed → propose setting status `done` and ticking the acceptance boxes;
- gaps → list them as concrete tasks to add to `tasks.md`.

Write everything in English. Fix nothing in this command — report only.
