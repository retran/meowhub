---
id: 0039
title: The agent's tools are a declared, validated contract in this repository
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0039 - The agent's tools are a declared, validated contract in this repository

## Context

ADR 0025 settled prompts: they're files in this repository, versioned, with
declared output schemas. It said nothing about the other half of the agent, and
that half is the one that writes to the books.

The agent doesn't only extract, it acts. It records a transaction, asks a
question, confirms a record, opens an account when an admin asks, answers a
query, and attributes an expense to a project. Each of those is a tool the model
can call, and a tool is far more dangerous than a prompt: a prompt that drifts
produces a wrong suggestion, while a loosely specified tool lets a model write
something nobody asked for.

Until this ADR, nothing said what the tools are, what they accept, who can call
them, or what happens when the model calls one with nonsense.

## Decision

Tools are declared artefacts with the same standing as migrations, held in this
repository beside the prompts they're offered to.

- Each tool declares a stable name, a one-line purpose the model sees, a JSON
  input schema, the permission it requires, and whether it reads or mutates. The
  declaration is the contract, and the workflow implements it.
- The tool layer validates input against the schema before anything executes. A
  call that fails validation is a failed parse, so it becomes an unparsed capture
  and a question, and never a partial write. This extends ADR 0025's rule from
  output to input.
- Mutating tools are few, and we name them all: record a transaction, correct
  one, confirm one, classify one, open or amend an account, merge, import, and
  undo. The model can't call anything off that list, and adding one changes this
  contract.
- Every mutating tool carries the acting member and executes with that member's
  authority. Row-level security enforces it (ADR 0014), so the tool layer never
  becomes a second, softer gate. A tool the acting member can't use fails at the
  database, and the model is told plainly.
- Structural tools confirm first. Opening an account or merging categories
  restates the change and waits (ADR 0031), so the tool returns a proposal
  instead of performing the change.
- Read tools return aggregates from the view catalogue (`data-model.md`) and
  never raw ledger rows, so the model sees no more of the books than the question
  needs (ADR 0029's data minimisation).
- No tool calls another tool. The model orchestrates, because a tool that calls
  two tools hides a decision the audit log should have recorded.
- Every call is logged with its name, input, result, and acting member
  (ADR 0008), which is what makes a wrong action explainable.
- Tool definitions are versioned like prompts, and a transaction records which
  version acted, so we can find a bad batch.

### How they are verified

A tool is tested twice. Its schema is tested with valid and deliberately
malformed input, and its effect is tested against a real database, including the
negative case where the wrong member calls it (ADR 0015). A tool without a
negative test isn't finished, because the failure that matters is the write that
should never have happened, not the crash.

## Alternatives

| Option | Why rejected |
|---|---|
| Let the agent write SQL | Maximum flexibility and no contract at all: a model with a SQL connection to the household's books can reach everything, and every mistake costs a migration to undo |
| Tools defined inside the workflow nodes | Where they naturally end up, invisible to review, impossible to diff, and lost on re-import, which is the same failure ADR 0025 fixed for prompts |
| One do-everything tool taking free-form instructions | A smaller declaration, unbounded behaviour, and nothing to validate |
| Trust the model to stay within its instructions | A prompt is a request, and only a schema and a permission make a boundary |
| Let tools compose for convenience | Hides intermediate decisions from the audit log, the one record that has to be complete |

## Consequences

Good:
- Anyone can list what the agent can do by reading one directory, and each entry
  is reviewable and testable.
- A loosely phrased instruction can't produce a write that no tool allows.
- Authority stays the member's and is enforced where it's already enforced, so
  we keep no second permission model in step with the first.
- A wrong action traces back to a tool version and an input.

Bad, and the price we accept:
- Every new agent capability now costs a contract change, a schema, a
  permission, and two tests. We want that friction, and it will still feel like
  bureaucracy the first time someone wants a one-line change.
- Schemas fit conversational input awkwardly: people say "около 350", and the
  schema wants a number. Converting it belongs in extraction, before the tool,
  which puts the pressure on prompts.
- More tools mean a longer list in the model's context on every call, which
  costs tokens on every capture.

What becomes harder to change later is a tool's name and input shape, once
transactions record which version acted, so we add a version instead of editing
one and the history stays honest.
