---
id: NNNN
title: <short feature name>
status: draft          # draft | review | approved | in-progress | done | rejected | superseded
created: YYYY-MM-DD
updated: YYYY-MM-DD
owner: <who is accountable>
supersedes: []         # ids of specs this one replaces
---

# NNNN — <name>

## Problem

What hurts today. For whom, in which situation. No solution here — only the pain.

## Why

The outcome we want, and how we will know it improved (a metric or an
observable sign).

## Users and scenarios

- **<role>** wants **<action>** so that **<outcome>**.

## Requirements

Numbered, verifiable, phrased as behaviour. No implementation.

- **R1.** The system must ...
- **R2.** When <condition>, the system must ...

## Scope

**In scope:**
-

**Out of scope (and why):**
-

## Acceptance criteria

Conditions under which the feature is done. Phrased so a test follows directly.

- [ ] **A1.** Given <state>, when <action>, then <result>.
- [ ] **A2.** ...

## Edge cases and failures

| Situation | Expected behaviour |
|---|---|
|  |  |

## Ergonomic cost

See [docs/standards/ergonomics.md](../../docs/standards/ergonomics.md). Answer all
four; "none" is a valid answer that has to be earned.

- **Who does more work after this ships, and how much?**
- **What queue or obligation does it create, and what drains it?**
- **What does it interrupt, and how often?**
- **What happens if nobody touches it for a month?**

## Non-functional requirements

Only what genuinely matters for this feature (latency, privacy, cost,
accessibility, compatibility). An empty section beats an invented one.

## Open questions

**What a question blocks** — not whether it is "important". A spec can be planned
and built while `deploy` and `data` questions are still open; only a `design`
question stops the work.

| Value | Meaning |
|---|---|
| `design` | The schema or the behaviour cannot be settled without it. **Blocks the plan.** |
| `build` | Needed during implementation — a real file, a credential, a verified assumption. Blocks a task, not the plan. |
| `deploy` | Only needed to go live or to operate: a provider, a domain, a purchase, a physical arrangement. |
| `data` | A household fact needed to *use* the system, not to build it. Development runs on the seeded synthetic household. |
| `nothing` | A preference with a sensible default. Recorded so it is a choice rather than an accident. |

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 |  | design/build/deploy/data/nothing | open |

## Related

- ADRs:
- Specs:
