# Architecture overview

> Early stage: we have decided the stack and built nothing yet. We update this
> document as each slice lands, so it always describes what actually exists.

## Context

meowhub serves one household from one installation: three members today, two of
them admins. We built it for that household alone, so it has no multi-tenancy,
no public sign-up and no external users, and everything runs on hardware the
household owns or rents.

You reach meowhub through a Telegram bot, from the regular Telegram clients on
the household's Apple devices. We plan no custom chat app, because a client we
write is one more thing to install on every phone.

```
household member ──► Telegram ──► n8n workflows ──► PostgreSQL
                                       │             (double-entry ledger,
                                       │              forecast tables, audit log)
                                       └──► OpenRouter (LLM)

household member ──► tunnel/proxy ──► Authentik ──► household app ──► PostgREST ──► SQL views
owner ─────────────────────────────────────────┴──► n8n editor
```

Ingress is a swappable edge (ADR 0002): a public reverse proxy on the VPS, an
outbound tunnel at home. No part of the system knows which one is in use, and on
a laptop there is no edge at all, because Telegram updates arrive by long polling
instead (ADR 0033) and the whole system runs against the seeded household.

[data-model.md](data-model.md) lists the entities and every view the product
reads. [../standards/budgets.md](../standards/budgets.md) holds the shared
latency, cost and size budgets, and [../risks.md](../risks.md) the delivery
risks.

## Components

Eight components make up the system. The table below gives each one its job and
the line it must not cross; the rest of this document explains why those lines
sit where they do.

| Component | Responsibility | Boundary |
|---|---|---|
| Telegram bot | The only user-facing interface: receives messages, sends replies | Owns no state; all logic lives in n8n |
| n8n | Orchestration and agent logic: parsing, tool calls, digests, scheduling, statement import | Writes to PostgreSQL, but not the only writer - the app writes corrections |
| Household app | Next.js + Tailwind, static build: trends, balances, corrections | Reads SQL views through PostgREST only; computes no totals of its own |
| PostgREST | The only data path for the app; enforces nothing itself | Authorisation is row-level security in PostgreSQL |
| Authentik | One authentication boundary for the app and the admin surfaces | Knows nothing about the ledger |
| Uptime Kuma | Health checks and heartbeats; the only thing that notices silence | Alerts go to the admins in Telegram |
| PostgreSQL | System of record: ledger, members, merchant registry, statements, audit log | Knows nothing about Telegram or LLMs; enforces its own rules via constraints and triggers |
| OpenRouter | Single gateway to language models | Stateless; every call is retryable |

## Where the data lives

The books, the files and the backups sit in the EU from day one, on the
household's own host and in EU object storage, and we allow no exception to
that.

Beyond those three, we treat EU residency as a direction we steer by and not as
a gate we block on ([ADR 0028](decisions/0028-eu-data-residency-as-a-direction.md)):
an EU region run by a non-EU company is acceptable. That ADR lists the three
accepted gaps, and nothing else in this repository repeats them - Telegram's
transit, the model gateway's calls, and Apple sign-in metadata. Each gap comes
with the step that closes it. All three sit in the capture and access paths, so
the ledger itself never leaves.

## Key decisions

[decisions/](decisions/) holds the full register, grouped and including the
superseded ones. Five decisions shape everything else:

- [0028](decisions/0028-eu-data-residency-as-a-direction.md) - EU residency as a
  direction, and the only place its gaps are listed
- [0011](decisions/0011-double-entry-ledger-and-chart-of-accounts.md) - the
  double-entry ledger, with [0031](decisions/0031-chart-of-accounts-and-categories-are-admin-managed.md)
  making the chart itself editable data
- [0014](decisions/0014-postgrest-and-row-level-security-as-the-data-api.md) -
  PostgREST over the views, with authorisation in row-level security
- [0030](decisions/0030-identity-is-ours-telegram-is-a-linked-channel.md) - a
  member is an account of ours; channels are links to it
- [0024](decisions/0024-secret-custody-and-recovery.md) - two custodians for
  every secret, and a rehearsed recovery

[docs/standards/threat-model.md](../standards/threat-model.md) says what the
access rules are for and what we do not defend against.

## Accepted constraints

These eleven rules bind almost every change we make, and each one costs us
something we agreed to pay. Break one and the review sends the change back.

- Every component must run on the home server, so we disqualify a service that
  cannot, however convenient it is. OpenRouter is the one exception we accepted
  (ADR 0029).
- The same Compose file must run on the VPS and at home, so we disqualify
  anything provider-specific. We treat this as a contract we can be held to.
- All three members write to one shared ledger, with attribution on every
  entry, because private ledgers would give us three sets of books that never
  reconcile.
- The database audits every change, whoever makes it, because more than one
  writer touches the data and a workflow-level audit would miss the app
  (ADR 0008).
- The mobile app shows the books and corrects them, and you capture an expense
  without opening a screen, so its only writes are corrections (ADR 0007).
- Only real events become postings, so budgets, commitments and plans live
  outside the ledger (ADR 0012).
- Every total comes from a SQL view, so the bot's digests and the app's screens
  read the same numbers and cannot disagree.
- A statement line carries where its number came from, and a model-derived one
  stays provisional until somebody confirms it, because we never want a guess
  filed as a reading (ADR 0013).
- You can reach everything on desktop from the keyboard (ADR 0037); the phone is
  thumb-first, and that keyboard rule does not touch it.
- Every mutating action has an inverse, which you reach by saying "undo" in the
  surface where you made the mistake (ADR 0036).
- Every transaction records whether a human or the bank vouched for it, so a
  guess and a checked record stay apart in the books as well (ADR 0023).

## Directions not yet taken

The household runs Apple devices and Siemens appliances, which makes Apple Home
and Home Connect the obvious things to integrate once the bookkeeping slices are
done. Neither is in scope yet, and neither should influence the current design
beyond the self-hosting constraint above.
