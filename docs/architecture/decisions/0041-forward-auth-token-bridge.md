---
id: 0041
title: Authentik authenticates the session; a token bridge mints the PostgREST JWT
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0041 - Authentik authenticates the session; a token bridge mints the PostgREST JWT

## Context

ADR 0006 puts Authentik in front of every surface as forward authentication at
the proxy, and ADR 0014 puts row-level security in front of the data, keyed on a
PostgREST JWT that carries a role and our own member identifier (spec 0002 R15,
R15a). Neither ADR says how the first becomes the second.

Authentik's forward-auth is a Proxy Provider that the reverse proxy checks on
every request. It proves who is signed in and hands the upstream a few headers:
a username, an email, a stable subject id, and group membership. It doesn't
produce the JWT PostgREST expects, which needs a `role` claim naming a
PostgreSQL role and a claim carrying our own member id, signed with
`PGRST_JWT_SECRET`. Authentik knows nothing about `member`, `member_identity`,
or which of our roles a group corresponds to, and it shouldn't, because ADR 0030
already decided that identity is ours and the provider is only a link.

R16a adds one more constraint: this token never reaches the browser. The app is
a static bundle we trust with nothing, so whatever mints the token runs
server-side, between the authenticated request and PostgREST.

## Decision

A small internal service, the token bridge, sits behind Authentik's forward-auth
and in front of PostgREST. For any data-API call, the reverse proxy first asks
Authentik's forward-auth whether the session is valid, then asks the token
bridge to mint a PostgREST JWT for this member, and then calls PostgREST with
the bridge's minted token in the Authorization header. The browser sees none of
the three and holds only a proxy session cookie.

- The bridge resolves an identity to a member, and doesn't translate one claim
  into another. Given Authentik's asserted subject id, it looks up
  `member_identity` (ADR 0030) to find the member row, and it reads Authentik's
  asserted group membership to choose between `hh_admin` and `hh_member`
  (ADR 0006's `admin` and `household` groups map onto spec 0002's two roles). A
  subject with no resolvable member is refused here, before the request reaches
  PostgREST, so R15a's "no resolvable member id" case is handled by never
  issuing a token.
- The minted token lives for minutes, because the bridge rebuilds it on every
  request from Authentik's live session and caches nothing from sign-in. A
  revoked passkey or a deactivated member (ADR 0026) stops the next
  request from getting a token, so nothing waits for a token to expire on its
  own.
- `PGRST_JWT_SECRET` lives only in the bridge and in PostgREST's own
  configuration. Authentik never holds it and never needs it, because Authentik
  authenticates the session and doesn't speak PostgREST's contract.
- The bridge holds the only copy of the role-mapping and member-resolution
  logic. Neither the proxy config nor PostgREST's configuration encodes which
  Authentik group is which database role, because that mapping is tested code
  and not a Caddyfile matcher.
- R16c's local developer path uses the same bridge. A documented local command
  asks the bridge for a token for a named test member and takes the minting path
  a real request takes, so development never depends on a separate, weaker
  mechanism.

## Alternatives

| Option | Why rejected |
|---|---|
| Configure Authentik as a full OIDC provider and have PostgREST or the proxy verify Authentik's own JWT directly | Authentik's token shape is Authentik's: no `role` claim naming a PostgreSQL role, and no member id. Every PostgREST-facing claim would still need translating, so this only moves the bridge's job into Authentik's token customization, which is configuration by clicks and therefore excluded by ADR 0010 |
| Sync Authentik users into a `member`-shaped table through its API on every login, and skip live resolution | Adds a second, eventually consistent copy of membership and role instead of reading the one that exists, so a deactivation (ADR 0026) would lag instead of taking effect on the next request |
| Let the app hold the PostgREST token after a one-time exchange | Contradicts R16a, because it puts a bearer token in the one place the design says holds no credential |
| Have n8n mint the token, since it already holds a direct database connection | Couples the ledger's orchestrator to every human request path; n8n's connection serves the agent, not every app and admin request |

## Consequences

Good:
- The mapping from role to member is one tested piece of code instead of logic
  split between an identity provider's UI and a proxy config.
- Revocation and deactivation take effect immediately, because nothing is cached
  past Authentik's own session validity.
- PostgREST's contract (ADR 0014) stays exactly as it is, so how the token
  arrives changes nothing about row-level security or the view catalogue.

Bad, and the price we accept:
- Every data-API call passes through one more component, and the app and n8n's
  forward-authenticated admin surfaces need it to be up at all. It's small and
  stateless and holds no data of its own, so it fails closed.
- An admin reading Authentik's UI can no longer see which group grants which
  database role, because that mapping now lives in the bridge's code. This ADR
  documents the mapping and a test covers it.

Replacing Authentik, or replacing PostgREST, stays as cheap as it was today:
each change touches one side of the bridge and leaves the other side's contract
as it is.
