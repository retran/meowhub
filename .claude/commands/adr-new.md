---
description: Draft a new architecture decision record
argument-hint: <the decision, in a phrase>
---

Draft an ADR for: $ARGUMENTS

1. Check it belongs here. An ADR records a decision that **outlives one feature**:
   a platform, a storage model, a protocol, a boundary, a standard. A decision
   scoped to one feature belongs in that feature's `plan.md`. If it is
   feature-scoped, say so and stop.
2. Take the next free number from `docs/architecture/decisions/` — sequential,
   never reused, independent of spec numbering. File:
   `NNNN-kebab-case-title.md`.
3. Read the ADRs it touches first. An ADR that contradicts an accepted one must
   either be wrong or supersede it — decide which, explicitly, and set
   `supersedes` / `superseded-by` on both.
4. Copy `specs/_templates/adr.md` and fill it in:
   - **Context**: the forces and constraints that make a decision necessary, with
     facts checked rather than recalled. Where a claim is about a tool's licence,
     tier or capability, verify it and say so.
   - **Decision**: what we do, affirmative and present tense.
   - **Alternatives**: every option genuinely considered, each with the reason it
     was rejected. Name the closest call — an ADR with no near-miss is usually
     under-researched.
   - **Consequences**: good, bad with the price we accept, and what becomes harder
     to change later. The bad section is the one that earns the document.
5. **Describe the decision, never the history of this document.** Write as though
   it was always this decision: no "previously", no "reconsidered after", no
   record of which option was adopted first. A rejected option gets its reason in
   the alternatives table, not its biography. Git history is where the movement
   lives.
6. Status starts `proposed`. Add the row to the register in
   `docs/architecture/decisions/README.md`, and to the decision list in
   `docs/architecture/overview.md` if it is in force.
7. If the decision changes how the product behaves, say which specs and which
   parts of `docs/product/vision.md` need updating — and update them in the same
   change, so the repository never describes two different systems.

Write in English. Show the user the decision, the closest alternative and the
price being accepted.
