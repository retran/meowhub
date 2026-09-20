# Spec-driven workflow

## Why

We argue about behaviour in text first because that is cheaper than rewriting an
implementation. A spec captures what would otherwise live in chat history and in
someone's head, and it leaves a basis a reviewer can verify.

## Artifacts

A change produces up to seven artifacts, and each one owns a different set of
facts.

| File | Answers | Source of truth for |
|---|---|---|
| `spec.md` | What and why: behaviour, scope, acceptance | system behaviour |
| `plan.md` | How: approach, alternatives, risks | the feature's technical solution |
| `tasks.md` | In what order: steps and progress | state of the work |
| `notes.md` | Scratch thinking | nothing (draft) |
| ADR | Project-level decisions | architecture |
| `docs/architecture/data-model.md` | Entities and every view the product reads | the contract between specs |
| `docs/standards/budgets.md` | Latency, cost and size baselines | what a spec's NFRs refine |

To decide where a statement belongs, ask whether it stops being true when we swap
a tool. If it does, write it in `plan.md` and not in `spec.md`.

## Lifecycle

A spec moves through seven statuses, and the front matter's `status` is the
source of truth for where it currently sits.

```
draft ──► review ──► approved ──► in-progress ──► done
  │          │
  └──────────┴──► rejected | superseded
```

- draft: someone is still writing it, and questions are still open.
- review: the author considers it complete and waits for agreement.
- approved: agreed, with no `design` question still open, so you can write the
  plan. An open `deploy` or `data` question doesn't hold a spec back, because a
  provider, a domain, a purchase, or the household's real balances aren't needed
  to design or build anything, and treating them as blockers stalls work that
  could have proceeded on the seeded household.
- in-progress: tasks exist and the implementation is under way.
- done: reviewed, with every acceptance criterion closed by evidence.
- rejected: we decided against it, and the spec stays with the reason appended.
- superseded: another spec replaced it, linked through `supersedes`.

We never delete a spec, because a cancelled spec is knowledge too.

## Numbering

A spec is numbered `NNNN`, four digits, and we never reuse a number. Spec numbers
and ADR numbers are independent sequences.

## What counts as trivial and skips the spec

Five kinds of change skip the spec: typos, formatting, dependency bumps with no
behaviour change, reverting a previous change, and edits to these documents.
Anything that changes observable product behaviour goes through a spec.

## Common mistakes

These seven mistakes come up most often in review, so check a draft against them
before you ask for agreement.

- Implementation in the spec. "Add a `users` table" belongs in the plan; the spec
  says "the system remembers who submitted an expense".
- Unverifiable acceptance. Replace "fast enough" with "answers within 3 seconds
  at the 95th percentile".
- Evidence that is a paragraph. Close a criterion by naming a passing test, or by
  recording a manual run where automation is genuinely impossible (ADR 0015).
  "Checked, works" closes nothing.
- An invented answer instead of an open question. When we don't know what the
  user wants, write a question rather than a guess dressed as a requirement.
- Calling everything blocking. Classify a question by *what it blocks* - design,
  build, deploy, data, or nothing - because conflating "we cannot deploy" with
  "we cannot build" is how a project waits for a domain name before writing a
  migration.
- Silent scope expansion. Shipping more than the spec asked for is as much a
  discrepancy as shipping less.
- A spec written after the code. It then records no decision and only reports
  what was built.
