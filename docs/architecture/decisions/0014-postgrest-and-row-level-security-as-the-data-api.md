---
id: 0014
title: PostgREST over the SQL views is the data API, with authorisation in row-level security
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0014 - PostgREST over the SQL views is the data API, with authorisation in row-level security

## Context

ADR 0007 commits us to a small application with no backend of its own. That only
works if something turns the ledger into an API without becoming a project in
itself, because otherwise "little code" comes back as a hand-written server with
its own auth, its own queries and its own bugs.

Two facts we already have make the API cheap. ADRs 0004 and 0011 require all
aggregation to live in SQL views, so the reporting surface exists whatever we
decide about an API. PostgreSQL can also enforce authorisation itself, which is
the part a hand-written backend would otherwise have to be trusted with.

## Decision

**PostgREST** runs in front of the household database and exposes the SQL views
and a narrow set of writable tables as REST. It is the only way the app reaches
data.

- The views are the API contract. We expose nothing that isn't deliberately a
  view or a table we granted on purpose, so a view's shape is a public interface
  and we change it through a migration that gets reviewed as one.
- Authorisation lives in the database, as row-level security policies on
  PostgreSQL roles. The app is a static bundle in the member's browser, so we can
  trust it with nothing, and what a member can read and correct stays the same
  whether the request comes from the app, from a workflow or from a psql
  session.
- Identity comes from the identity provider. Authentik (ADR 0032) issues the
  token, PostgREST validates it and adopts the role and member identifier it
  carries, and the policies key on that identifier. The bot and the app share one
  identity model: a member is a member.
- Writes are deliberately narrow: corrections and merchant merges only, through
  functions or views that enforce the double-entry invariant (ADR 0011). Nothing
  can insert a raw posting, and capture stays in the chat.
- n8n keeps its direct database connection, because the orchestrator runs
  server-side, we already trust it, and it needs transactions and bulk
  operations that REST would only make more awkward.

## Alternatives

| Option | Why rejected |
|---|---|
| A hand-written API (Node, Go, Python) | The thing ADR 0007 exists to avoid. Every endpoint would re-express a view, and authorisation would move out of the database into code we then have to trust and test |
| Hasura | Auto-generated GraphQL and good subscriptions, but GraphQL costs more than it gives a three-person read-mostly app, and it is heavier to operate |
| Directus | REST plus GraphQL plus an admin UI and roles over an existing database, which is genuinely attractive and would also cover back-office repair. We rejected it because its licence moved to BSL 1.1, which we would have to read before adopting it, and because it is more product than we need next to an app we are building anyway |
| Supabase self-hosted | The same PostgREST, wrapped in fifteen or more containers we would then have to operate |
| The app queries PostgreSQL directly | Puts credentials in the browser, or forces the backend we just declined |
| Exposing tables rather than views | Makes the physical schema the public contract, so we could not refactor a table without breaking the app |

## Consequences

**Good:**
- We have no backend to write, deploy or maintain: one small container with
  almost no configuration of its own.
- The database enforces authorisation in one place for every client, so the app,
  the workflows and a psql session all get the same answer.
- Filtering, ordering and pagination come with PostgREST, so the app doesn't
  implement them.
- The API falls out of the views the ledger already owed us, instead of adding a
  layer.

**Bad, and the price we accept:**
- A sloppy view becomes a public interface, so we have to design each view
  rather than let it accrete: the app depends on its shape.
- Row-level security is subtle, and a mistake there leaks data between household
  members instead of crashing. Policies need their own tests, at the level of
  "this member cannot see that row".
- Because REST follows the schema, some screens need a purpose-built view rather
  than a clever query, which means more migrations.
- One more component sits in the request path, with its own JWT configuration to
  get right between it and Authentik.

**What becomes harder to change later:**
- View signatures, once the app binds to them, which is the coupling any API
  has. When a breaking change is genuinely needed we version the view instead of
  mutating it.
