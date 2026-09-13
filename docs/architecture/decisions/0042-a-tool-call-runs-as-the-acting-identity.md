---
id: 0042
title: A tool call writes as the member it acts for, never as the agent alone
status: accepted
date: 2026-09-13
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0042 — A tool call writes as the member it acts for, never as the agent alone

## Context

ADR 0039 declares that every action the agent performs goes through a declared
tool, with a validated input schema and "the acting member's authority" — but it
does not say what that phrase becomes at the database. Spec 0002 already put two
distinct roles behind row-level security, `hh_admin` and `hh_member`, plus a
third, `hh_agent`, for the bot's own unattended writes (T12's Telegram-linking
gate mints `hh_agent` tokens to resolve a sender, never to act on their behalf).
Spec 0003 is the first slice where the agent both composes a write of its own
(a capture, extracted from a free-text message) and carries out a write a member
explicitly asked for (a correction, a deletion, a confirmation, a structural
change) — and those are not the same authority.

If every tool call minted the same `hh_agent` token regardless of who asked,
"a member who is not an admin attempts to delete a transaction" (A17) would only
ever be refused if some workflow step remembered to check the requester's role
first. That check would live in n8n, next to the permissions RLS already
enforces, and the two would drift the moment one changed without the other —
exactly the second, softer gate ADR 0039 exists to rule out. A negative test
against the workflow would prove the workflow behaves; it would prove nothing
about the database, which is where ADR 0014 puts authorisation.

## Decision

**A tool call mints the PostgREST token of the identity actually responsible
for the write, not always the agent's own.**

- **A capture the agent composed from a free-text message** — extracting an
  amount, a merchant, a category from what a member typed — mints `hh_agent`
  with that member's `member_id`. The agent is acting on the household's behalf
  to interpret the message; the row's `submitter` is still the member (spec
  0003 R6), because `hh_agent`'s grants already shape what it may insert, not
  who gets credited.
- **Anything a member explicitly asked for** — correct this, delete that,
  confirm this, open an account, merge two categories — mints the token of the
  **acting member's own role**: `hh_admin` or `hh_member`, with their
  `member_id`. The tool does not decide whether they may do it; it asks
  PostgreSQL to, by writing as them.
- **The distinction is what the request is**, not which workflow step happens
  to run it. A structural change is always a member's own request (R0c: the
  agent never creates an account unasked), so it always mints the requester's
  role. A capture is always the agent's composition, even when triggered by a
  member's message, so it always mints `hh_agent`.
- **A tool declaration names which shape it uses** (ADR 0039's contract gains
  this field): `composes` for the `hh_agent`-with-member-id shape, `acts_as` for
  the requester's-own-role shape. The declaration is checked, not trusted — the
  same schema validation that already rejects malformed input rejects a tool
  claiming a shape its own permission does not allow.
- **This is a restatement of ADR 0039's existing rule**, not a new principle:
  "a tool the acting member may not use must fail at the database" only holds
  if the database is asked as that member. Minting `hh_agent` unconditionally
  would make that sentence untestable.

## Alternatives

| Option | Why rejected |
|---|---|
| The agent always writes as `hh_agent`, and a tool refuses to call the database if the requester's role does not allow it | Puts the permission model in n8n, next to and separate from row-level security — untestable by impersonation, and the two definitions can silently disagree (exactly what ADR 0039 was written to prevent) |
| Grant `hh_agent` the union of every permission it might need on a member's behalf | Makes `hh_agent`'s own grants the real authorisation boundary, which then has to be as fine-grained as the member/admin distinction anyway — at which point it is the same design with an extra hop |
| A separate `hh_agent_admin` role for admin-requested actions | Multiplies roles for a distinction that is already `hh_admin` versus `hh_member`; nothing about "the agent typed the SQL" needs its own role once the acting member's own role is used directly |

## Consequences

**Good:**
- A4, A14, A17 and A42 (a member exceeding their role, an unpermitted tool)
  fail at row-level security, exactly where every other permission in this
  project is proven — by impersonation, never by reading a workflow's
  conditional logic.
- The audit log's actor (`meowhub.actor`, set from the JWT's `member_id` by
  `pgrst_pre_request()`) is always a real member for a member-requested action,
  never a generic "bot" actor standing in for one.
- Extending the tool surface never means extending what `hh_agent` itself may
  do — a new admin-only tool is safe by construction the moment its grants are
  admin-only, with no corresponding n8n check to remember.

**Bad, and the price we accept:**
- Two token shapes exist in the same workflow rather than one, and a tool's
  declaration must say which it needs — one more thing to get right when a new
  tool is added, checked by A42's negative test.
- Minting a token per call, per shape, is marginally more work than minting one
  and reusing it for a whole conversation turn; this is the same trade-off
  ADR 0041 already accepted for the browser path, for the same reason
  (nothing is cached past what the request needs).

**What becomes harder to change later:** nothing. Both shapes already exist as
PostgREST tokens with a `role` and a `member_id` claim (ADR 0041); this decision
only fixes which one a given tool call uses, not the mechanism itself.
