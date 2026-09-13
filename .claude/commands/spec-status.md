---
description: Overview of all specs, their status and progress
---

Report the state of all specs.

1. Walk `specs/*/` (excluding `_templates`), read the `spec.md` front matter
   and count progress in `tasks.md` (closed/total).
2. Print a table: `id | title | status | artifacts (spec/plan/tasks) | task
   progress | blocking questions`.
3. Then list separately:
   - specs waiting on the user, separated by what is waited for: an open `design`
     question (which blocks the plan) versus `deploy` or `data` answers (which do
     not);
   - specs `in-progress` with all tasks closed but no review yet;
   - specs whose artifacts are out of sync (for example status `done` while
     `tasks.md` still has open tasks).
4. Read the ADRs in `docs/architecture/decisions/` and flag any still
   `proposed`.

Write everything in English. Close with a single recommendation for the next
sensible step.
