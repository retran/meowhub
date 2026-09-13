---
id: 0039
title: The agent's tools are a declared, validated contract in this repository
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0039 — The agent's tools are a declared, validated contract in this repository

## Context

ADR 0025 settled prompts: files in this repository, versioned, with declared
output schemas. It left the other half of the agent unspecified, and it is the
half that writes to the books.

The agent does not only extract — it **acts**: records a transaction, asks a
question, confirms a record, opens an account when an admin asks, answers a query,
attributes an expense to a project. Each of those is a tool the model may call,
and a tool is a far more dangerous interface than a prompt: a prompt that drifts
produces a wrong suggestion, while a tool that is loosely specified lets a model
write something nobody asked for.

Nothing currently says what the tools are, what they accept, who may call them, or
what happens when the model calls one with nonsense.

## Decision

**Tools are declared artefacts with the same standing as migrations**, held in
this repository beside the prompts they are offered to.

- **Each tool declares** a stable name, a one-line purpose the model sees, a JSON
  input schema, the permission it requires, and whether it is read-only or
  mutating. The declaration is the contract; the workflow implements it.
- **Input is validated against the schema before anything executes.** A call that
  fails validation is a failed parse — an unparsed capture and a question — never a
  partial write (ADR 0025's rule, extended from output to input).
- **Mutating tools are few and named.** Record a transaction, correct one, confirm
  one, classify one, open or amend an account, merge, import, undo. Anything not on
  the list is not callable, and adding one is a change to this contract.
- **Every mutating tool carries the acting member** and executes with that
  member's authority. Row-level security is the enforcement (ADR 0014); the tool
  layer never becomes a second, softer gate. A tool the acting member may not use
  fails at the database, and the model is told plainly.
- **Structural tools confirm first.** Opening an account or merging categories
  restates and waits (ADR 0031), which means the tool returns a proposal rather
  than performing the change.
- **Read tools return aggregates, never raw ledger rows**, and only from the view
  catalogue (`data-model.md`). The model never sees more of the books than the
  question needs (ADR 0029's data minimisation).
- **No tool composes others.** The model orchestrates; a tool that calls two tools
  hides a decision the audit log should have recorded.
- **Every call is logged** with its name, input, result and acting member
  (ADR 0008) — which is what makes a wrong action explainable rather than
  mysterious.
- **Tool definitions are versioned like prompts**, and a transaction records which
  version acted, so a bad batch is findable.

### How they are verified

A tool is tested twice: its **schema**, with valid and deliberately malformed
input; and its **effect**, against a real database, including the negative case
that the wrong member cannot call it (ADR 0015). A tool with no negative test is
not finished — the failure that matters is not the crash, it is the write that
should not have happened.

## Alternatives

| Option | Why rejected |
|---|---|
| Let the agent write SQL | Maximum flexibility and no contract at all: a model with a SQL connection to the household's books has the whole surface, and every mistake is a migration to undo |
| Tools defined inside the workflow nodes | Where they naturally end up, invisible to review, undiffable, and lost on re-import — the same failure ADR 0025 fixed for prompts |
| One do-everything tool taking free-form instructions | Smaller declaration, unbounded behaviour, and nothing to validate |
| Trust the model to stay within its instructions | A prompt is a request, not a boundary. The boundary is a schema and a permission |
| Let tools compose for convenience | Hides intermediate decisions from the audit log, which is the one record that has to be complete |

## Consequences

**Good:**
- The set of things the agent can do is enumerable, reviewable and testable — a
  question anyone can answer by reading one directory.
- A loosely phrased instruction cannot produce a write that no tool allows.
- Authority is the member's, enforced where it is already enforced, so there is no
  second permission model to keep in step.
- A wrong action is traceable to a tool version and an input.

**Bad, and the price we accept:**
- Every new agent capability is now a contract change, a schema, a permission and
  two tests. That friction is the point, and it will feel like bureaucracy the
  first time a one-line change is wanted.
- Schemas for conversational inputs are awkward: people say "около 350", and the
  schema wants a number. The conversion belongs in extraction, before the tool,
  which puts pressure on prompts rather than on tools.
- More tools mean a longer list in the model's context on every call, which costs
  tokens on every capture.

**What becomes harder to change later:** a tool's name and input shape, once
transactions record which version acted. Versioning rather than editing is what
keeps the history honest.
