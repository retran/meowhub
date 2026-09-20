---
id: NNNN
title: <short feature name>
status: draft          # draft | review | approved | in-progress | done | rejected | superseded
created: YYYY-MM-DD
updated: YYYY-MM-DD
owner: <who is accountable>
supersedes: []         # ids of specs this one replaces
---

# NNNN - <name>

## Problem

What hurts today, for whom, and in which situation. Name the person and the
moment, and give the reason the pain exists. Describe no solution here, only the
pain.

## Why

The outcome we want, and how we will know it improved. Name a metric or an
observable sign somebody could check without asking you.

## Users and scenarios

- **<role>** wants **<action>** so that **<outcome>**.

## Requirements

Number every requirement, phrase it as behaviour a test can check, and keep the
implementation out of it. Where a requirement follows from a constraint or an
ADR, say so in the same sentence.

- **R1.** The system must ...
- **R2.** When <condition>, the system must ...

## Scope

**In scope:**
-

**Out of scope (and why):**
-

## Acceptance criteria

The conditions under which the feature is done, phrased so that an implementer
can write the test straight from the sentence.

- [ ] **A1.** Given <state>, when <action>, then <result>.
- [ ] **A2.** ...

## Edge cases and failures

| Situation | Expected behaviour |
|---|---|
|  |  |

## Ergonomic cost

Answer all four questions below; see
[docs/standards/ergonomics.md](../../docs/standards/ergonomics.md). "None" is a
valid answer, and you earn it by saying why nobody does more work.

- **Who does more work after this ships, and how much?**
- **What queue or obligation does it create, and what drains it?**
- **What does it interrupt, and how often?**
- **What happens if nobody touches it for a month?**

## Non-functional requirements

Write down only what genuinely matters for this feature - latency, privacy, cost,
accessibility, compatibility - with the number or the limit that makes it
checkable. If nothing here matters for this feature, leave the section empty; an
invented limit is one nobody will check.

## Open questions

Classify each question by what it blocks, not by how important it feels. A spec
can be planned and built while `deploy` and `data` questions are still open, and
only a `design` question stops the work.

| Value | Meaning |
|---|---|
| `design` | The schema or the behaviour cannot be settled without it. **Blocks the plan.** |
| `build` | Needed during implementation - a real file, a credential, a verified assumption. Blocks a task, not the plan. |
| `deploy` | Only needed to go live or to operate: a provider, a domain, a purchase, a physical arrangement. |
| `data` | A household fact needed to *use* the system, not to build it. Development runs on the seeded synthetic household. |
| `nothing` | A preference with a sensible default. Recorded so that it is a choice rather than an accident. |

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 |  | design/build/deploy/data/nothing | open |

## Related

- ADRs:
- Specs:
