---
id: 0044
title: The agent keeps its own memory, separate from the ledger and from conversation state
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0044 — The agent keeps its own memory, separate from the ledger and from conversation state

## Context

Two kinds of state already exist for the agent, and neither is memory in the
sense a household actually wants:

- **The ledger** (ADR 0011) is the household's financial record. A fact that
  is not a transaction has no home there, and putting one there would be
  exactly the "invented financial fact" ADR 0031 exists to prevent.
- **`conversation`** (ADR 0038) is a single exchange in progress, closed once
  resolved. It is deliberately short-lived and disposable — nothing in it
  survives being answered.

What is missing is somewhere for the agent to keep a fact worth carrying
into a *later, unrelated* exchange: "the household is saving for a car this
year," "the daughter prefers not to be asked which account," "Albert Heijn
online orders should default to groceries even though the model keeps
guessing dining." None of these are transactions, none belong to one
conversation, and losing them the moment a conversation closes makes the
agent forget things a person in the room would not.

## Decision

**`agent_memory` is a household-visible note the agent writes and reads on
its own**, distinct from both the ledger and any one conversation.

- **One row is one fact**, free text, optionally scoped to a member
  (`member_id`, nullable — null means household-wide) or left unscoped for
  something true of the household generally.
- **The agent writes it through a declared tool** (`remember`, ADR 0039),
  the same `composes` shape as recording a capture (ADR 0042) — writing a
  memory is the agent's own act, not something a member explicitly asked
  for, the same way creating an unreviewed category is (ADR 0031).
- **The agent reads relevant memory as context**, the same way it already
  reads known merchants and accounts when composing a capture — a fact
  in memory can change how the *next* message is interpreted, never what a
  past transaction was.
- **Never a financial fact.** Memory cannot be cited as the reason a
  transaction has a particular amount, account or confirmation state — only
  provenance (ADR 0008) can be. Memory informs a question or a default; it
  never substitutes for asking when the ledger's own invariants need an
  answer.
- **Visible and editable like anything else an admin owns.** An admin may
  read, correct or delete any memory row — a wrong or stale memory is a
  data problem, not a prompt problem, and fixing it should not require a
  prompt change.
- **Not an unbounded log.** This is deliberately a *small* table of standing
  facts, not a transcript — `capture` already keeps the full transcript
  (R6a). A memory row is written because the agent judged it worth keeping
  past the conversation that produced it, not automatically for everything
  said.

## Alternatives

| Option | Why rejected |
|---|---|
| No memory; every conversation starts cold | What existed before this decision, and it is why the household is asking for this: a person who forgets everything between visits is not the assistant the product wants to be |
| Store memory as a column on `member` | A member can have many standing facts, not one; a single free-text column becomes an unstructured dumping ground with no way to reason about individual facts (list them, delete one, scope one to the household instead) |
| Derive "memory" from the audit log or conversation history at read time | Re-deriving intent from prose on every request, at model cost, with a different answer each time — the same reasoning ADR 0038 already rejected for conversation state, and it applies here identically |
| Let the agent write memory freely, with no tool declaration | Contradicts ADR 0039 directly: every write the agent makes goes through a declared, validated tool, and memory is no exception just because it feels lower-stakes than a transaction |
| Auto-summarise every conversation into memory | Produces memory nobody asked for and nobody reviews, at model cost, for facts that are mostly not worth keeping. The agent deciding deliberately, via a tool call, is what keeps the table small and the facts in it actually useful |

## Consequences

**Good:**
- The agent can carry a standing fact across conversations without inventing
  a place for it in the ledger or stretching `conversation` past its own
  purpose.
- An admin can inspect, correct or remove exactly what the agent
  "remembers," the same way they can inspect anything else it wrote.
- Memory writes are auditable and permissioned like every other agent
  action (ADR 0042) — a `remember` call is `hh_agent`, gated the same way a
  captured transaction is.

**Bad, and the price we accept:**
- One more table whose value depends on the agent using it well — a model
  that never calls `remember` gets no benefit, and one that calls it for
  everything defeats the "small table of standing facts" intent. Judging
  that boundary lives in the prompt, not the schema, and prompts drift
  (ADR 0025 is the mitigation: golden-set scoring, versioned).
- A stale memory is a new failure mode: a fact that was once true and no
  longer is, sitting uncorrected until an admin notices. Named here rather
  than discovered later.

**What becomes harder to change later:** nothing structural. This is
additive — nothing before it depended on the agent having no memory, and
nothing here prevents a later slice from giving memory more structure
(categories of fact, expiry) if a free-text row turns out not to be enough.
