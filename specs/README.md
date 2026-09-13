# Specs

One directory per feature: `NNNN-kebab-case-slug/`.

```
NNNN-slug/
  spec.md     what and why (source of truth for behaviour)
  plan.md     how (written when the slice is started)
  tasks.md    steps and progress
  notes.md    scratch notes, if a slice needs them
```

Templates live in [`_templates/`](_templates/). The process and the status
model are described in
[docs/standards/spec-driven-workflow.md](../docs/standards/spec-driven-workflow.md).

New spec: `/spec-new <description>`. Overview: `/spec-status`.

Each spec's open questions are classified by **what they block** — `design`,
`build`, `deploy`, `data` or `nothing`. Only a `design` question holds a spec
back. Development runs against the seeded synthetic household, so the
household's real balances, a hosting provider, a domain and an Apple membership
are not needed to design or build anything: they are needed to go live.

A spec's number is permanent once anything references it. While a spec is still
`draft` and unreferenced, renumbering is allowed — that is how slices get
inserted in front of unwritten ones.

## Index

| # | Feature | Status |
|---|---|---|
| [0001](0001-infrastructure-bootstrap/spec.md) | Infrastructure bootstrap | **approved** · plan and tasks written |
| [0002](0002-identity-and-access/spec.md) | Identity and access | review |
| [0003](0003-text-expense-capture/spec.md) | Chart of accounts, opening balances and text expense capture | review |
| [0004](0004-queries-and-digest/spec.md) | Chat queries and the scheduled digest | review |
| [0005](0005-multimodal-capture/spec.md) | Multimodal capture — receipt photos and voice notes | review |
| [0006](0006-household-app/spec.md) | The household app — trends, balances, corrections and approvals | review |
| [0007](0007-statement-import/spec.md) | Statement import and reconciliation | review |
| [0008](0008-borrowing/spec.md) | Borrowing — card settlement, overdraft interest, fees and loans | review |
| [0009](0009-budgets-and-commitments/spec.md) | Budgets, commitments and the forecast | review |
| [0010](0010-wishlist-and-projects/spec.md) | The wishlist and projects | review |
| [0011](0011-home-server-migration/spec.md) | Migration to the home server | review |

The order these are built in, and the documentation that goes with each, is in
[docs/implementation-plan.md](../docs/implementation-plan.md).

Every slice now has a spec. The order they are built in, and why that order, is in
[docs/product/vision.md](../docs/product/vision.md), which is the authority on
sequence.
