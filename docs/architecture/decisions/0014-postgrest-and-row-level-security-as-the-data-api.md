---
id: 0014
title: PostgREST over the SQL views is the data API, with authorisation in row-level security
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0014 — PostgREST over the SQL views is the data API, with authorisation in row-level security

## Context

ADR 0007 commits to a small application with no backend of its own. That only
works if something turns the ledger into an API without becoming a project in
itself — otherwise "little code" reappears as a hand-written server, with its own
auth, its own queries and its own bugs.

Two facts make this cheap. ADRs 0004 and 0011 already require that **all
aggregation live in SQL views**, so the reporting surface exists regardless of any
API decision. And PostgreSQL can enforce authorisation itself, which is the part a
hand-written backend would otherwise have to be trusted with.

## Decision

**PostgREST** runs in front of the household database and exposes the SQL views
and a narrow set of writable tables as REST. It is the only way the app reaches
data.

- **The views are the API contract.** Nothing is exposed that is not deliberately
  a view or an explicitly granted table. A view's shape is therefore a public
  interface and changes to it are migrations, reviewed as such.
- **Authorisation lives in the database**, as row-level security policies on
  PostgreSQL roles — not in the app, which is a static bundle in the member's
  browser and can be trusted with nothing. What a member may read and correct is
  the same whether the request comes from the app, from a workflow or from a
  psql session.
- **Identity comes from the identity provider.** Authentik (ADR 0032) issues the
  token; PostgREST validates it and adopts the role and member identifier it
  carries; policies key on that identifier. One identity model for the bot and the
  app: a member is a member.
- **Writes are deliberately narrow.** Corrections and merchant merges only,
  through functions or views that enforce the double-entry invariant (ADR 0011);
  nothing may insert a raw posting. Capture stays in the chat.
- **n8n keeps its direct database connection.** The orchestrator is server-side,
  trusted, and needs transactions and bulk operations — routing it through REST
  would be ceremony.

## Alternatives

| Option | Why rejected |
|---|---|
| A hand-written API (Node, Go, Python) | The thing ADR 0007 exists to avoid. Every endpoint would re-express a view, and authorisation would move out of the database into code that has to be trusted and tested |
| Hasura | Auto-generated GraphQL and good subscriptions, but GraphQL for a three-person read-mostly app is ceremony, and it is heavier to operate |
| Directus | REST plus GraphQL plus an admin UI and roles over an existing database — genuinely attractive, and it would also cover back-office repair. Rejected because its licence moved to BSL 1.1, which needs reading before adoption, and because it is more product than this needs alongside an app we are building anyway |
| Supabase self-hosted | The same PostgREST, wrapped in fifteen or more containers we would then operate |
| The app queries PostgreSQL directly | Puts credentials in the browser, or forces the backend we just declined |
| Exposing tables rather than views | Makes the physical schema the public contract, so no table can be refactored without breaking the app |

## Consequences

**Good:**
- No backend to write, deploy or maintain: one small container with almost no
  configuration of its own.
- Authorisation is enforced in one place, in the database, for every client.
- Filtering, ordering and pagination come free, so the app does not implement
  them.
- The API is a direct consequence of work the ledger already owed us — views —
  rather than a new layer.

**Bad, and the price we accept:**
- **Sloppy views become a public interface.** The discipline has to be real: a
  view is designed, not accreted, because the app depends on its shape.
- Row-level security is subtle, and a mistake there is a data leak between
  household members rather than a crash. Policies need tests of their own, at the
  level of "this member cannot see that row".
- REST shaped by the schema means some screens need a purpose-built view rather
  than a clever query, which is more migrations.
- One more component in the request path, with its own JWT configuration to get
  right between it and Authentik.

**What becomes harder to change later:**
- View signatures, once the app binds to them — the same coupling any API has.
  Mitigated by versioning a view rather than mutating it when a breaking change
  is genuinely needed.
