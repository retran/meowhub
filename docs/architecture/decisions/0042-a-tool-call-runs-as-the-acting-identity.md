---
id: 0042
title: A tool call writes as the member it acts for, never as the agent alone
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0042 - A tool call writes as the member it acts for, never as the agent alone

## Context

ADR 0039 says every action the agent performs goes through a declared tool, with
a validated input schema and "the acting member's authority", but it doesn't say
what that phrase becomes at the database. Spec 0002 already put two roles behind
row-level security, `hh_admin` and `hh_member`, plus a third, `hh_agent`, for
the bot's own unattended writes; T12's Telegram-linking gate mints `hh_agent`
tokens to resolve a sender and never to act on the sender's behalf. Spec 0003 is
the first slice where the agent does both: it composes a write of its own, a
capture extracted from a free-text message, and it carries out a write a member
explicitly asked for, such as a correction, a deletion, a confirmation, or a
structural change. Those two are different authorities.

If every tool call minted the same `hh_agent` token whoever asked, then "a
member who is not an admin attempts to delete a transaction" (A17) would be
refused only when some workflow step remembered to check the requester's role
first. That check would live in n8n, beside the permissions row-level security
already enforces, and the two would drift as soon as one changed without the
other, which is the second, softer gate ADR 0039 exists to rule out. A negative
test against the workflow would prove that the workflow behaves and would prove
nothing about the database, which is where ADR 0014 puts authorisation.

## Decision

A tool call mints the PostgREST token of the identity responsible for the write,
which isn't always the agent's own.

- A capture the agent composed from a free-text message, by extracting an
  amount, a merchant, and a category from what a member typed, mints `hh_agent`
  with that member's `member_id`. The agent interprets the message on the
  household's behalf, and the row's `submitter` is still the member (spec 0003
  R6), because `hh_agent`'s grants shape what it can insert and not who gets
  credited.
- Anything a member explicitly asked for, such as correct this, delete that,
  confirm this, open an account, or merge two categories, mints the token of the
  acting member's own role, `hh_admin` or `hh_member`, with their `member_id`.
  The tool doesn't decide whether they can do it; it writes as them and lets
  PostgreSQL decide.
- What the request is decides the shape, and not which workflow step runs it. A
  structural change is always a member's own request, because R0c says the agent
  never creates an account unasked, so it always mints the requester's role. A
  capture is always the agent's composition, even when a member's message
  triggered it, so it always mints `hh_agent`.
- A tool declaration names which shape it uses, which adds a field to
  ADR 0039's contract: `composes` for the `hh_agent`-with-member-id shape, and
  `acts_as` for the requester's-own-role shape. The declaration is checked, so
  the schema validation that already rejects malformed input also rejects a tool
  that claims a shape its own permission doesn't allow.
- This restates ADR 0039's rule instead of adding a principle. "A tool the
  acting member may not use must fail at the database" holds only when we ask
  the database as that member, and minting `hh_agent` unconditionally would make
  that sentence untestable.

## Alternatives

| Option | Why rejected |
|---|---|
| The agent always writes as `hh_agent`, and a tool refuses to call the database when the requester's role doesn't allow it | Puts the permission model in n8n, beside and separate from row-level security, where impersonation can't test it and the two definitions can silently disagree, which is what ADR 0039 was written to prevent |
| Grant `hh_agent` the union of every permission it might need on a member's behalf | Makes `hh_agent`'s own grants the real authorisation boundary, which would then have to be as fine-grained as the split between member and admin, so it's the same design with an extra hop |
| A separate `hh_agent_admin` role for admin-requested actions | Adds roles for a distinction `hh_admin` and `hh_member` already draw, since using the acting member's own role leaves nothing about "the agent typed the SQL" that needs a role of its own |

## Consequences

Good:
- A4, A14, A17, and A42, which cover a member exceeding their role and an
  unpermitted tool, fail at row-level security, where every other permission in
  this project is proven, by impersonation and not by reading a workflow's
  conditional logic.
- The audit log's actor, `meowhub.actor`, which `pgrst_pre_request()` sets from
  the JWT's `member_id`, is always a real member for a member-requested action
  instead of a generic bot actor standing in for one.
- Extending the tool surface never extends what `hh_agent` itself can do, so a
  new admin-only tool is safe the moment its grants are admin-only, with no n8n
  check to remember.

Bad, and the price we accept:
- The same workflow now uses two token shapes, and each tool's declaration has
  to say which one it needs, which is one more thing to get right when someone
  adds a tool; A42's negative test checks it.
- Minting a token per call and per shape is slightly more work than minting one
  and reusing it for a whole conversation turn. ADR 0041 already accepted this
  trade-off for the browser path, for the same reason: nothing is cached past
  what the request needs.

Nothing becomes harder to change later. Both shapes already exist as PostgREST
tokens with a `role` and a `member_id` claim (ADR 0041), and this decision fixes
which one a given tool call uses without touching the mechanism.
