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

# ADR 0046 — The agent is one tool-calling loop that writes its own replies

## Context

Specs 0001–0003 built the agent as a router, a prompt per task, and a workflow
per task that did the database work in code around a single model call. Spec
0004's plan added a fourth prompt whose only job was to turn a question into a
query name. Three problems are visible in the code that resulted:

- **The agent cannot choose anything.** `capture-text` resolves a merchant by
  substring-matching an alias list in JavaScript, and creates one when nothing
  matches; a category and a payment account are resolved the same way. The model
  returns a string and hopes. Every decision that actually needs judgement —
  *is this the Albert Heijn we already know, or a new shop?* — is taken by the
  part of the system least able to take it.
- **Every new kind of message costs a prompt.** A new task means a new system
  prompt, a new output schema, a new set of examples, a new workflow and another
  alternation in the entry point's routing regex, which had reached eight by
  spec 0003's T13.
- **Templated replies can only answer anticipated questions.** "How much on food
  and transport together" has no template, so it has no answer, even though the
  figures for both sit in the same view.

A tool-calling loop is the ordinary shape for this, and it is small: call the
model with the tool list, execute whatever tools it asks for, feed the results
back, stop when it returns prose instead of a tool call.

## Decision

**One agent: one system prompt, one loop, tools for everything it touches, and
every reply written by the agent itself.**

- **One conversational entry point.** A member's message is normalised and handed
  to the agent. There is no trigger-phrase routing between conversational
  workflows, because there is one conversational workflow.
- **One system prompt** — the persona, the household's rules, and what the agent
  must never do. Not one per task. Capture, correction, setup, questions and
  search are things the agent does with tools, not separate programs.
- **Tools cover the decisions, not only the writes.** Finding a merchant among
  the ones already known, creating one when it is genuinely new, listing the
  household's categories, proposing a new one, finding which account a member
  meant — each is a declared tool the agent calls, not logic wrapped around it.
- **The model chooses what; the executor chooses as whom; the database decides
  whether.** A tool's executor mints the token for the acting identity
  (ADR 0042). The agent naming a tool is a request, never an authorisation.
- **The agent composes every reply it sends**, in the member's own language.
- **The loop is bounded**: a fixed maximum number of rounds per message. An
  exhausted budget, a failing tool or an unreachable model degrades to the
  unparsed path (a stored message and an honest sentence), never to a guess.

### What this does not change

- **The declared tool contract** (ADR 0039), the **acting-identity rule**
  (ADR 0042), **conversation state in the database** (ADR 0038), and every
  row-level policy and guard trigger. The agent may ask for anything; the
  database is what refuses, and that is now the only thing standing between a
  confused model and the books — which is why those guards are tested by
  impersonation rather than through the bot.
- **No figure is computed outside SQL.** The agent reads figures out of tool
  results and puts them in a sentence. It does no arithmetic on money, and a
  period-over-period difference is a column, not a subtraction it performs
  (ADR 0045).
- **Scheduled work stays model-free and separate.** A digest is SQL and a
  template, sent on a schedule with no agent involved: it must be reproducible,
  identical to what a question would answer, and free of commentary by
  construction rather than by instruction.
- **The message catalogue keeps everything the system says without the agent** —
  digests, scheduled notices, denials issued before any model is called, and the
  failure vocabulary.

## Alternatives

| Option | Why rejected |
|---|---|
| One agent, one prompt, tools, agent-written replies | **chosen** — see Decision |
| A prompt and a workflow per task, replies from a catalogue | What we had. It cannot answer an unanticipated question, it puts merchant and category choice in substring matching, and each new capability costs four files and a regex |
| Keep the per-task prompts but let each write its own reply | Removes the templates without removing the routing or the JavaScript judgement, so the agent still cannot decide anything and still cannot answer across two tools |
| One agent, but keep a mapping step that picks the tool before the loop | Two model calls to do what one loop does, and the mapping step is the thing that cannot answer a compound question. The loop already picks tools — that is what a loop is |
| Let the model write SQL instead of calling tools | Unbounded and un-reviewable, and it destroys the refusal path: there is no declared set to be outside of (ADR 0045 rejected the same thing for periods) |

## Consequences

**Good:**
- The agent can do what the tools can do, in combination, without anyone
  anticipating the combination — including questions spanning two views.
- Merchant and category choice move to the only participant with the context to
  make them, and "is this a new merchant?" becomes an explicit decision with an
  explicit tool rather than a substring match.
- Four prompts become one, three conversational workflows become one, and the
  routing regexes go away entirely.
- Adding a capability is adding a tool. Nothing else changes.

**Bad, and the price we accept:**
- **A templated reply could be checked word by word; an agent's cannot.** The
  guarantee becomes a property — every figure in a reply appears in the tool
  results that produced it, and no figure appears that does not — and that check
  has to be real, because nothing else now stands between a model and a wrong
  number in front of the household.
- More tokens per exchange: the tool list and the growing history go up on every
  round, where a single extraction call went up once.
- One prompt serving every job is one place to regress: a change made to improve
  questions can quietly hurt capture. The golden set has to cover both, which is
  what ADR 0025 already demands before a prompt change is accepted.
- A model that calls tools badly can loop, so the round cap is load-bearing
  rather than defensive.

**What becomes harder to change later:** the tool boundary. Once the agent's
competence is exactly "whatever the tools expose", work that no tool covers is
invisible to it — so a capability added to the app without a tool is a
capability the household cannot ask for, which is the failure ADR 0045's own
registry check (spec 0004, A5b) exists to catch.
