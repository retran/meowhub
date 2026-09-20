---
id: 0044
title: The agent keeps its own memory, separate from the ledger and from conversation state
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0044 - The agent keeps its own memory, separate from the ledger and from conversation state

## Context

The agent already has two kinds of state, and neither is memory in the sense the
household wants:

- The ledger (ADR 0011) is the household's financial record. A fact that isn't a
  transaction has no home there, and putting one there would create exactly the
  invented financial fact that ADR 0031 exists to prevent.
- `conversation` (ADR 0038) holds a single exchange in progress and closes once
  the exchange resolves, so it's deliberately short-lived and nothing in it
  survives being answered.

Neither holds a fact worth carrying into a later, unrelated exchange: "the
household is saving for a car this year," "the daughter prefers not to be asked
which account," "Albert Heijn online orders should default to groceries even
though the model keeps guessing dining." None of those are transactions, none
belong to one conversation, and losing them when a conversation closes makes the
agent forget what a person in the room would remember.

## Decision

`agent_memory` is a household-visible note the agent writes and reads on its
own, separate from the ledger and from any one conversation.

- One row holds one fact, in free text, optionally scoped to a member through a
  nullable `member_id`. A null `member_id` means the fact is true of the
  household generally.
- The agent writes memory through a declared tool, `remember` (ADR 0039), using
  the same `composes` shape as recording a capture (ADR 0042), because writing
  a memory is the agent's own act and not something a member explicitly asked
  for, just as creating an unreviewed category is (ADR 0031).
- The agent reads relevant memory as context, the way it already reads known
  merchants and accounts when composing a capture. A fact in memory can change
  how the agent interprets the next message, and it never changes what a past
  transaction was.
- Memory is never a financial fact. Nothing in memory can be cited as the reason
  a transaction has a particular amount, account, or confirmation state, because
  only provenance (ADR 0008) can be. Memory informs a question or a default, and
  it doesn't replace asking when the ledger's invariants need an answer.
- Memory is visible and editable like anything else an admin owns. An admin can
  read, correct, or delete any memory row, because a wrong or stale memory is a
  data problem and fixing it shouldn't cost a prompt change.
- Memory isn't an unbounded log. We keep a small table of standing facts,
  because `capture` already keeps the full transcript (R6a). The agent writes a
  row when it judges the fact worth keeping past the conversation that produced
  it, not automatically for everything said.

## Alternatives

| Option | Why rejected |
|---|---|
| No memory; every conversation starts cold | What we had before this decision, and the reason the household asked for memory, because an assistant that forgets everything between visits isn't what the product promises |
| Store memory as a column on `member` | A member has many standing facts, so a single free-text column becomes an unstructured dumping ground with no way to list facts, delete one, or scope one to the household |
| Derive memory from the audit log or conversation history at read time | Re-derives intent from prose on every request, at model cost, with a different answer each time, which is the reasoning ADR 0038 already used to reject the same idea for conversation state |
| Let the agent write memory freely, with no tool declaration | Contradicts ADR 0039, which sends every write the agent makes through a declared, validated tool, and memory feeling lower-stakes than a transaction doesn't exempt it |
| Auto-summarise every conversation into memory | Produces memory nobody asked for and nobody reviews, at model cost, for facts that are mostly not worth keeping; the agent deciding through a tool call is what keeps the table small and the facts useful |

## Consequences

Good:
- The agent can carry a standing fact across conversations without inventing a
  place for it in the ledger or stretching `conversation` past its purpose.
- An admin can inspect, correct, or remove exactly what the agent remembers, the
  same way they inspect anything else it wrote.
- Memory writes are audited and permissioned like every other agent action
  (ADR 0042), because a `remember` call runs as `hh_agent` and is gated the same
  way a captured transaction is.

Bad, and the price we accept:
- One more table whose value depends on the agent using it well. A model that
  never calls `remember` gains nothing, and one that calls it for everything
  loses the small table of standing facts we wanted. The prompt draws that
  boundary, not the schema, and prompts drift, which is why ADR 0025 versions
  them and scores them against a golden set.
- A stale memory is a new failure mode: a fact that was once true sits
  uncorrected until an admin notices it. We name it here so nobody discovers it
  later.

Nothing structural becomes harder to change later. This decision only adds:
nothing before it depended on the agent having no memory, and nothing here stops
a later slice from giving memory more structure, such as categories of fact or
expiry, if a free-text row turns out not to be enough.
