---
description: Break an implementation plan into ordered tasks
argument-hint: <NNNN — spec number>
---

Load the `technical-english` skill before drafting: `tasks.md` is a how-to guide whose reader is the implementer.

Break the plan for spec $ARGUMENTS into tasks.

1. Read `spec.md` and `plan.md` from `specs/$ARGUMENTS-*/`. If `plan.md` is
   missing, stop and suggest `/spec-plan` first.
2. Copy `specs/_templates/tasks.md` into the spec directory and fill it in.
3. Decomposition rules:
   - each task is one logical commit; after it the project still works and its
     checks pass;
   - every task has explicit dependencies, references to requirements (`R*`)
     and a verifiable done-when condition;
   - the order must never leave a task blocked;
   - tests are not a final separate task — they sit inside the task whose
     behaviour they verify;
   - every acceptance criterion (`A*`) is covered by at least one task. Check
     coverage and report any `A*` left uncovered.
4. Do not shred into micro-steps like "create a file". The right granularity is
   a meaningful change in behaviour.

Write everything in English.

Show the task list and mark which tasks can run in parallel.
