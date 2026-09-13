---
description: Implement a spec's tasks in order
argument-hint: <NNNN [T3] — spec number, optionally a single task>
---

Implement tasks for: $ARGUMENTS

1. Read `spec.md`, `plan.md` and `tasks.md` from the spec directory. If
   `tasks.md` is missing, stop and suggest `/spec-tasks`.
2. Set the spec status to `in-progress` in the `spec.md` front matter and
   update `updated`.
3. If a specific task was named, do that one. Otherwise take the first open
   task whose dependencies are all closed.
4. For each task:
   - mark it `[~]` in `tasks.md` before starting;
   - implement exactly its scope, nothing more;
   - verify the done-when condition explicitly, not by eyeballing;
   - mark it `[x]` and move on.
5. If the work reveals that the spec or the plan is wrong, **stop**: record the
   discrepancy in the deviation log in `tasks.md`, propose the spec or plan
   change, and wait for the user's decision. Never bend code around a wrong
   spec, and never edit the spec silently.
6. When all tasks are closed, say so and suggest `/spec-review`. Status `done`
   is only set after review.

Write everything in English, including commit messages.

Do not commit or push until the user asks.
