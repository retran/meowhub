---
id: 0041
title: Authentik authenticates the session; a token bridge mints the PostgREST JWT
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0041 — Authentik authenticates the session; a token bridge mints the PostgREST JWT

## Context

ADR 0006 puts Authentik in front of every surface as forward authentication at
the proxy, and ADR 0014 puts row-level security in front of the data itself,
keyed on a PostgREST JWT carrying a role and our own member identifier
(spec 0002 R15, R15a). Neither ADR says how one becomes the other.

Authentik's forward-auth (a Proxy Provider, checked by the reverse proxy on
every request) proves who is signed in and hands the upstream a handful of
headers — a username, an email, a stable subject id, group membership. It does
not, by itself, produce a JWT shaped the way PostgREST expects: a `role` claim
naming a PostgreSQL role, and a claim carrying our own member id, signed with
`PGRST_JWT_SECRET`. Authentik knows nothing about `member`, `member_identity`
or which of our roles a group corresponds to — nor should it; ADR 0030 already
decided identity is ours and the provider is a link.

R16a additionally requires that this token never reach the browser: the app is
a static bundle trusted with nothing, so whatever mints the token must sit
server-side, between the authenticated request and PostgREST, not in it.

## Decision

**A small internal service, the token bridge, sits behind Authentik's
forward-auth and in front of PostgREST.** The reverse proxy's request path for
any data-API call is: Authentik forward-auth (is this session valid?) → the
token bridge (mint a PostgREST JWT for this member) → PostgREST, with the
proxy carrying the bridge's minted token into the Authorization header of the
final request. The browser sees none of the three; it only ever holds a proxy
session cookie.

- **The bridge resolves identity to a member, not a claim to a claim.** Given
  Authentik's asserted subject id, it looks up `member_identity` (ADR 0030) to
  find the member row, and Authentik's asserted group membership to decide
  `hh_admin` versus `hh_member` (ADR 0006's `admin`/`household` groups map onto
  spec 0002's two roles). A subject with no resolvable member is refused here,
  before PostgREST is ever reached — R15a's "no resolvable member id" case is
  satisfied by never issuing a token, not by issuing one PostgREST then
  rejects.
- **The minted token is short-lived** — minutes, not hours — because it is
  reconstructed on every request from Authentik's live session rather than
  cached from sign-in. A revoked passkey or a deactivated member (ADR 0026)
  stops minting new ones on the very next request; nothing waits for a token
  to expire on its own.
- **`PGRST_JWT_SECRET` lives only in the bridge and in PostgREST's own
  configuration.** Authentik never holds it, and never needs to: it authenticates
  the session, it does not speak PostgREST's contract.
- **The bridge is the one place role-mapping and member resolution logic live.**
  Neither the proxy config nor PostgREST's own configuration encodes "which
  Authentik group is which database role" — that mapping is code, tested, not
  a Caddyfile matcher.
- **R16c's local developer path uses the same bridge.** A documented local
  command asks the bridge for a token for a named test member, the same
  minting path a real request would take — never a separate, weaker mechanism
  kept only for development.

## Alternatives

| Option | Why rejected |
|---|---|
| Configure Authentik as a full OIDC provider and have PostgREST or the proxy verify Authentik's own JWT directly | Authentik's token shape is Authentik's, not PostgREST's — no `role` claim naming a PostgreSQL role, no member id. Every PostgREST-facing claim would still need translating somewhere; this option only moves the bridge's job into Authentik's own token customization, which is configuration-as-clicks (ADR 0010 excludes it) rather than tested code |
| Sync Authentik users into a `member`-shaped table via its API on every login, skip live resolution | Adds a second, eventually-consistent copy of membership and role instead of reading the one that exists; a deactivation (ADR 0026) would lag rather than take effect on the next request |
| Let the app hold the PostgREST token after a one-time exchange | Directly contradicts R16a: a bearer token in the browser is a credential in the one place the design says there is none |
| Have n8n mint the token, since it already holds a direct database connection | Couples the ledger's orchestrator to every human request path; n8n's connection is for the agent, not for arbitrating every app and admin request |

## Consequences

**Good:**
- The role/member mapping is one tested piece of code, not logic split across
  an identity provider's UI and a proxy config.
- Revocation and deactivation take effect immediately, because nothing is
  cached past Authentik's own session validity.
- PostgREST's contract (ADR 0014) stays exactly what it already is; nothing
  about row-level security or the view catalogue changes because of how the
  token arrives.

**Bad, and the price we accept:**
- One more component in the request path for every data-API call, and one more
  place that must be up for the app or n8n's forward-auth'd admin surfaces to
  work at all. It is small, stateless, and holds no data of its own, which
  keeps its own failure mode simple: it fails closed.
- The mapping from Authentik groups to database roles is now a fact that lives
  in this bridge's code rather than being visible in Authentik's own UI —
  documented here and tested, not hidden.

**What becomes harder to change later:** nothing structural. Replacing
Authentik, or replacing PostgREST, only changes one side of the bridge; the
other side's contract is unchanged.
