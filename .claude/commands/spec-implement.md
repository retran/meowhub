---
description: Implement a spec's tasks in order
argument-hint: <NNNN [T3] — spec number, optionally a single task>
---

Load the `technical-english` skill first. It governs the task notes you write, the deviation log entries, and the commit message that closes the slice.

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
   - verify the done-when condition explicitly, not by eyeballing — but keep
     this verification narrow: run only that task's own targeted test
     script(s) against the already-running dev stack. Do **not** run the full
     `task test` suite and do **not** do a full clean rebuild (drop volumes,
     rebuild images, `task up`, `task seed`, `task test`) after every task —
     that heavy loop runs once, at the end, in step 6. A migration needed
     mid-task still gets applied and exercised normally; just don't reach for
     the full-suite hammer per task;
   - mark it `[x]` and move on.
5. If the work reveals that the spec or the plan is wrong, **stop**: record the
   discrepancy in the deviation log in `tasks.md`, propose the spec or plan
   change, and wait for the user's decision. Never bend code around a wrong
   spec, and never edit the spec silently.
6. When all tasks are closed: run the full clean rebuild once (drop volumes,
   rebuild images, `task up` alone, `task seed`, `task test` alone, each
   checked by its real exit code) and confirm every task's targeted test
   still passes against it. Then commit — **one commit for the whole spec**,
   not one per task — and say so, suggesting `/spec-review`. Status `done`
   is only set after review.

Write everything in English, including commit messages.

Commit messages follow Conventional Commits and carry **no attribution
trailer of any kind** — see *Commits* in `CLAUDE.md`. A slice is
`feat(spec-NNNN): ...`; its body says why, names the real bugs found, and
says what proved the work.

Do not commit or push until the user asks.
