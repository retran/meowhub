# Architecture overview

> Early stage: the stack is decided, nothing is built yet. This document is
> updated as each slice lands, and always describes what actually exists.

## Context

meowhub is a single-tenant system: one installation serves one household —
currently three members, two of them admins. There is no multi-tenancy, no public sign-up and no
external users. Everything runs on infrastructure the household owns or rents.

The primary entry point is a Telegram bot. The household's Apple devices reach
it through the regular Telegram clients; no custom app is planned.

```
household member ──► Telegram ──► n8n workflows ──► PostgreSQL
                                       │             (double-entry ledger,
                                       │              forecast tables, audit log)
                                       └──► OpenRouter (LLM)

household member ──► tunnel/proxy ──► Authentik ──► household app ──► PostgREST ──► SQL views
owner ─────────────────────────────────────────┴──► n8n editor
```

Ingress is a swappable edge (ADR 0002): a public reverse proxy on the VPS, an
outbound tunnel at home. Nothing inside the system depends on which is in use —
and locally there is no edge at all, because Telegram updates arrive by long
polling instead (ADR 0033), so the whole system runs on a laptop with the seeded
household.

The entities, and the catalogue of every view the product reads, are in
[data-model.md](data-model.md). The shared latency, cost and size budgets are in
[../standards/budgets.md](../standards/budgets.md), and the delivery risks in
[../risks.md](../risks.md).

## Components

| Component | Responsibility | Boundary |
|---|---|---|
| Telegram bot | The only user-facing interface: receives messages, sends replies | Owns no state; all logic lives in n8n |
| n8n | Orchestration and agent logic: parsing, tool calls, digests, scheduling, statement import | Writes to PostgreSQL, but not the only writer — the app writes corrections |
| Household app | Next.js + Tailwind, static build: trends, balances, corrections | Reads SQL views through PostgREST only; computes no totals of its own |
| PostgREST | The only data path for the app; enforces nothing itself | Authorisation is row-level security in PostgreSQL |
| Authentik | One authentication boundary for the app and the admin surfaces | Knows nothing about the ledger |
| Uptime Kuma | Health checks and heartbeats; the only thing that notices silence | Alerts go to the admins in Telegram |
| PostgreSQL | System of record: ledger, members, merchant registry, statements, audit log | Knows nothing about Telegram or LLMs; enforces its own rules via constraints and triggers |
| OpenRouter | Single gateway to language models | Stateless; every call is retryable |

## Where the data lives

**The books, the files and the backups are in the EU from day one** — the
household's own host and EU object storage. That part has no exceptions.

Beyond it, EU residency is a direction rather than a gate
([ADR 0028](decisions/0028-eu-data-residency-as-a-direction.md)): an EU region at
a non-EU company is acceptable, and three gaps are accepted and listed there and
nowhere else — Telegram's transit, the model gateway's calls, and Apple sign-in
metadata. Each carries the step that closes it. All three are in the capture and
access paths; the ledger never leaves.

## Key decisions

The full register, grouped and with the superseded ones, is in
[decisions/](decisions/). The five that shape everything else:

- [0028](decisions/0028-eu-data-residency-as-a-direction.md) — EU residency as a
  direction, and the only place its gaps are listed
- [0011](decisions/0011-double-entry-ledger-and-chart-of-accounts.md) — the
  double-entry ledger, with [0031](decisions/0031-chart-of-accounts-and-categories-are-admin-managed.md)
  making the chart itself editable data
- [0014](decisions/0014-postgrest-and-row-level-security-as-the-data-api.md) —
  PostgREST over the views, with authorisation in row-level security
- [0030](decisions/0030-identity-is-ours-telegram-is-a-linked-channel.md) — a
  member is an account of ours; channels are links to it
- [0024](decisions/0024-secret-custody-and-recovery.md) — two custodians for
  every secret, and a rehearsed recovery

What the access rules are for, and what we do not defend against, is in
[docs/standards/threat-model.md](../standards/threat-model.md).

## Accepted constraints

- **No component may be un-self-hostable.** A service that cannot run on the
  home server is disqualified, however convenient it is. OpenRouter is the one
  accepted exception (ADR 0029).
- **Portability is a contract, not an aspiration.** The same Compose file runs
  on the VPS and at home; anything provider-specific is disqualified.
- **Single shared ledger.** All three members write to one ledger with
  attribution, not to private ledgers.
- **Every change is audited, whoever makes it.** Enforced in the database, not in
  the workflows, because there is more than one writer (ADR 0008).
- **The mobile app is for looking, not for entering.** Capture requires no
  screen; the app's only writes are corrections (ADR 0007).
- **Only real events are postings.** Budgets, commitments and plans live outside
  the ledger (ADR 0012).
- **All aggregation is SQL views.** The bot's digests and the app's screens read
  the same views, so they cannot disagree.
- **A parsed number and a guessed number are never the same thing.** Statement
  lines carry their provenance, and model-derived ones are provisional (ADR 0013).
- **Nothing on desktop is reachable only by mouse** (ADR 0037); the phone is
  thumb-first and untouched by that model.
- **Every mutating action has an inverse**, reachable by saying "undo" in the
  surface where the mistake was made (ADR 0036).
- **A guessed record and a checked record are never the same thing either.**
  Every transaction carries whether a human or the bank has vouched for it
  (ADR 0023).

## Directions not yet taken

The household runs Apple devices and Siemens appliances, which makes Apple Home
and Home Connect the obvious integration targets once the bookkeeping slices are
done. Neither is in scope yet, and neither should influence the current design
beyond the self-hosting constraint above.
