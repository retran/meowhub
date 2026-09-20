---
id: 0046
title: The agent is one tool-calling loop that writes its own replies
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
amends: [0017, 0025, 0029, 0040]
---

# ADR 0046 - The agent is one tool-calling loop that writes its own replies

## Context

Specs 0001 to 0003 built the agent as a router, one prompt per task, and one
workflow per task that did the database work in code around a single model call.
Spec 0004's plan added a fourth prompt whose only job was turning a question into
a query name. The code that resulted has three problems.

The agent can't choose anything. `capture-text` resolves a merchant by
substring-matching an alias list in JavaScript and creates a merchant when
nothing matches, and it resolves a category and a payment account the same way.
The model returns a string and hopes. So the decisions that need judgement, such
as whether this is the Albert Heijn we already know or a new shop, are taken by
the part of the system least able to take them.

Every new kind of message costs a prompt. A new task means a new system prompt,
a new output schema, a new set of examples, a new workflow, and another
alternation in the entry point's routing regex, which had reached eight by spec
0003's T13.

Templated replies answer only the questions we anticipated. "How much on food
and transport together" has no template, so it has no answer, even though the
figures for both sit in the same view.

A tool-calling loop is the ordinary shape for this, and it's small: call the
model with the tool list, execute whatever tools it asks for, feed the results
back, and stop when it returns prose instead of a tool call.

## Decision

We build one agent: one system prompt, one loop, tools for everything it
touches, and every reply written by the agent itself.

- One conversational entry point takes a member's normalised message and hands
  it to the agent. No trigger phrase routes between conversational workflows,
  because there's one conversational workflow.
- One system prompt carries the persona, the household's rules, and what the
  agent must never do. Capture, correction, setup, questions, and search are
  things the agent does with tools, so none of them gets a prompt of its own.
- Tools cover the decisions as well as the writes: finding a merchant among the
  ones already known, creating one when it's genuinely new, listing the
  household's categories, proposing a new one, and finding which account a
  member meant. The agent calls each of those as a declared tool instead of
  running inside logic wrapped around it.
- The model chooses what to call, the executor chooses whose identity to call it
  as by minting the token for the acting identity (ADR 0042), and the database
  decides whether the call succeeds. The agent naming a tool is a request and
  never an authorisation.
- The agent composes every reply it sends, in the member's own language.
- The loop is bounded by a fixed maximum number of rounds per message. An
  exhausted budget, a failing tool, or an unreachable model falls back to the
  unparsed path, which stores the message and answers with an honest sentence,
  and it never falls back to a guess.

### What this does not change

- The declared tool contract (ADR 0039), the acting-identity rule (ADR 0042),
  conversation state in the database (ADR 0038), and every row-level policy and
  guard trigger all stand. The agent can ask for anything, and the database is
  what refuses; since that's now the only thing standing between a confused
  model and the books, we test those guards by impersonation instead of through
  the bot.
- No figure is computed outside SQL. The agent reads figures out of tool results
  and puts them in a sentence, does no arithmetic on money, and reads a
  period-over-period difference as a column rather than subtracting (ADR 0045).
- Scheduled work stays model-free and separate. A digest is SQL and a template
  sent on a schedule with no agent involved, so it's reproducible, identical to
  what a question would answer, and free of commentary by construction.
- The message catalogue keeps everything the system says without the agent:
  digests, scheduled notices, denials issued before any model is called, and the
  failure vocabulary.

## Alternatives

| Option | Why rejected |
|---|---|
| One agent, one prompt, tools, agent-written replies | Chosen; the Decision section gives the reasons |
| A prompt and a workflow per task, replies from a catalogue | What we had: it can't answer an unanticipated question, it puts merchant and category choice in substring matching, and each new capability costs four files and a regex |
| Keep the per-task prompts but let each write its own reply | Removes the templates and keeps the routing and the JavaScript judgement, so the agent still decides nothing and still can't answer across two tools |
| One agent, but keep a mapping step that picks the tool before the loop | Spends two model calls on what one loop does, and the mapping step is the part that can't answer a compound question, since picking tools is what a loop already does |
| Let the model write SQL instead of calling tools | Unbounded, impossible to review, and it destroys the refusal path, because no declared set exists to fall outside of; ADR 0045 rejected the same idea for periods |

## Consequences

Good:
- The agent can combine what the tools do without anyone anticipating the
  combination, including questions that span two views.
- Merchant and category choice move to the only participant with the context to
  make them, so "is this a new merchant?" becomes an explicit decision behind an
  explicit tool instead of a substring match.
- Four prompts become one, three conversational workflows become one, and the
  routing regexes go away.
- Adding a capability means adding a tool, and nothing else changes.

Bad, and the price we accept:
- We could check a templated reply word by word, and we can't check an agent's,
  so the guarantee becomes a property instead: every figure in a reply appears
  in the tool results that produced it, and no other figure appears. That check
  has to be real, because nothing else now stands between a model and a wrong
  number in front of the household.
- Each exchange costs more tokens, because the tool list and the growing history
  go up on every round, where a single extraction call went up once.
- One prompt serving every job is one place to regress, so a change made to
  improve questions can quietly hurt capture. The golden set has to cover both,
  which is what ADR 0025 already demands before a prompt change is accepted.
- A model that calls tools badly can loop, so the round cap does real work
  rather than sitting there as a defence.

What becomes harder to change later is the tool boundary. Once the agent's
competence is exactly what the tools expose, work no tool covers is invisible to
it, so a capability added to the app without a tool is a capability the
household can't ask for. ADR 0045's registry check (spec 0004, A5b) exists to
catch that.
