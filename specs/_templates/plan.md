---
spec: NNNN
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# NNNN - Implementation plan

> This plan answers how. When the plan and the spec disagree, we fix the spec
> first and then the plan.

## Approach

One or two paragraphs: the strategy we chose, and the reason we chose this one
over the others. Name the constraint that decided it.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
|  |  |  | chosen / rejected |

## Affected areas

Which parts of the system change, and how each one changes. Name the new
workflows and the contracts that move.

## Contracts and data

The public interfaces, message formats and table schemas that other parts will
depend on. Anything listed here is something a later slice can break by
accident, so give each one its columns, its types and its meaning.

## Migration and compatibility

What happens to the data and the clients that already exist. Say whether the
change needs a feature flag, and whether it can be reversed.

## Verification strategy

What the tests cover and at which level, and what you check by hand and how.
Every acceptance criterion from the spec appears in the table below, so that
closing one means citing a named passing test.

| Acceptance criterion | How we verify it |
|---|---|
| A1 |  |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
|  |  |  |

## ADRs required

The decisions in this plan that outlive the feature, each of which has to become
an ADR before the slice closes. Write "none" when the plan only implements
decisions that already exist, and name them.
