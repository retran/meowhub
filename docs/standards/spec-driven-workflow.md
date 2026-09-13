# Spec-driven workflow

## Why

Arguing about behaviour in text is cheaper than rewriting an implementation.
A spec captures what would otherwise live in chat history and in someone's head,
and leaves a verifiable basis for review.

## Artifacts

| File | Answers | Source of truth for |
|---|---|---|
| `spec.md` | What and why: behaviour, scope, acceptance | system behaviour |
| `plan.md` | How: approach, alternatives, risks | the feature's technical solution |
| `tasks.md` | In what order: steps and progress | state of the work |
| `notes.md` | Scratch thinking | nothing (draft) |
| ADR | Project-level decisions | architecture |
| `docs/architecture/data-model.md` | Entities and every view the product reads | the contract between specs |
| `docs/standards/budgets.md` | Latency, cost and size baselines | what a spec's NFRs refine |

Separation rule: if a statement stops being true when we swap a tool, it belongs
in `plan.md`, not in `spec.md`.

## Lifecycle

```
draft ──► review ──► approved ──► in-progress ──► done
  │          │
  └──────────┴──► rejected | superseded
```

- **draft** — being written, questions still open.
- **review** — the author considers it complete and awaits agreement.
- **approved** — agreed, with no `design` question still open. The plan may be
  written. Open `deploy` and `data` questions do **not** hold a spec back: a
  provider, a domain, a purchase or the household's real balances are not needed
  to design or build anything, and treating them as blockers stalls work that
  could have proceeded on the seeded household.
- **in-progress** — tasks exist, implementation is under way.
- **done** — reviewed, every acceptance criterion closed with evidence.
- **rejected** — decided against. The spec stays, with the reason appended.
- **superseded** — replaced by another spec, linked via `supersedes`.

Specs are never deleted. A cancelled spec is knowledge too.

## Numbering

`NNNN`, four digits, never reused. Spec numbers and ADR numbers are independent
sequences.

## What counts as trivial and skips the spec

Typos, formatting, dependency bumps with no behaviour change, reverting a
previous change, edits to these documents. Anything that changes observable
product behaviour goes through a spec.

## Common mistakes

- **Implementation in the spec.** "Add a `users` table" is a plan. The spec says
  "the system remembers who submitted an expense".
- **Unverifiable acceptance.** "Fast enough" → "answers within 3 seconds at the
  95th percentile".
- **Evidence that is a paragraph.** A criterion is closed by a named passing test,
  or by a recorded manual run where automation is genuinely impossible
  (ADR 0015). "Checked, works" closes nothing.
- **An invented answer instead of an open question.** If we do not know what the
  user wants, that is a question, not a guess dressed as a requirement.
- **Calling everything blocking.** A question is classified by *what it blocks* —
  design, build, deploy, data, or nothing. Conflating "we cannot deploy" with "we
  cannot build" is how a project waits for a domain name before writing a
  migration.
- **Silent scope expansion.** Shipping more than the spec asked for is as much a
  discrepancy as shipping less.
- **A spec written after the code.** Then it is not a decision record, it is a
  report.
