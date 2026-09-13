# Architecture Decision Records

An ADR records a project-level decision: the context, the choice, the rejected
alternatives and the price. One file per decision. A file is not rewritten after
acceptance — a decision that turns out wrong is replaced by a new ADR linked via
`superseded-by`.

File naming: `NNNN-kebab-case-title.md`, numbering is sequential and never reused.
Template: [`specs/_templates/adr.md`](../../../specs/_templates/adr.md).

**An ADR describes the decision, never the history of the document.** It reads as
though the decision was always this one: no "previously we said", no "reconsidered
after", no record of which option was adopted first. A rejected option appears in
the alternatives table with the reason it was rejected — not with its biography.
How the thinking moved is what git history is for. Once an ADR is `accepted` it
stops being edited at all: a decision that turns out wrong is replaced by a new
ADR, linked through `superseded-by`.

## Status, and what it commits us to

| Status | Meaning |
|---|---|
| `proposed` | Drafted, not yet agreed. Editable in place. |
| `accepted` | Agreed and binding. **The file is frozen**: a decision that turns out wrong is replaced by a new ADR linked through `superseded-by`, never rewritten. |
| `rejected` | Considered and declined. Kept, because the reasoning is the value. |
| `superseded` | Replaced by a later ADR, which is named in `superseded-by`. |
| `accepted`, with `amended-by` | Still in force, with **one clause** changed by a later ADR — which names the clause. Used when a decision is right except in a detail, so the alternative would be reissuing a long document to change a sentence. The amending ADR is the current word on that clause only. |
| `deprecated` | No longer applies, and nothing replaced it. |

Every live decision in this register is `accepted`: the household has agreed all
of them, and none is speculative. Three are `superseded` — ADR 0003 became 0029 when per-task routing, spend caps
and a residency ladder were added; ADR 0005 became 0030 when identity stopped
being a Telegram id; and ADR 0006 became 0032 when email and password joined the
sign-in methods, taking a purchase off the critical path. Four carry an
`amended-by`: 0010 on where settings live (0034), 0011 and 0017 on the clause about the chart living in migrations,
and 0027 on two clauses — Telegram as the source of identity (0030) and updates arriving by webhook (0033).

**References may be retargeted mechanically** when an ADR is superseded, so that
active documents point at the live decision. The reasoning inside a frozen ADR is
never edited. That is a real commitment — the first time
implementation contradicts one of these, the answer is a new ADR that supersedes
it, not an edit. Which is the point: the reasoning behind a reversal is worth more
than a tidy file.

## How to read this set

Twenty-six decisions is a lot to meet at once. They group like this:

- **Platform and hosting** — [0027](0027-telegram-as-the-conversational-platform.md)
  Telegram as the interface, [0001](0001-n8n-as-automation-platform.md) n8n,
  [0002](0002-self-hosted-docker-compose-topology.md) Compose and ingress,
  [0029](0029-model-gateway-and-per-task-routing.md) the model gateway.
- **The books** — [0004](0004-postgresql-as-system-of-record.md) PostgreSQL as
  system of record, [0011](0011-double-entry-ledger-and-chart-of-accounts.md)
  double-entry and the chart of accounts,
  [0018](0018-dbmate-for-migrations.md) migrations,
  [0031](0031-chart-of-accounts-and-categories-are-admin-managed.md) the chart as data,
  [0008](0008-append-only-audit-log-in-postgresql.md) the audit log.
- **Looking forward** — [0012](0012-plans-budgets-and-commitments-are-not-postings.md)
  budgets, commitments and plans as forecast objects,
  [0021](0021-projects-and-wishlist.md) projects and the wishlist.
- **The agent** — [0025](0025-prompts-are-versioned-bilingual-artefacts.md) prompts,
  [0039](0039-the-agents-tools-are-a-declared-contract.md) tools,
  [0038](0038-conversation-state-lives-in-the-database.md) conversation state,
  [0040](0040-workflows-are-small-named-and-composed.md) workflow conventions.
- **Getting data in** — [0013](0013-statement-ingestion-structured-first-pdf-via-model.md)
  statement ingestion, [0019](0019-content-addressed-file-storage-on-a-volume.md)
  file storage, [0023](0023-human-confirmation-of-model-derived-records.md)
  confirmation of model-derived records,
  [0025](0025-prompts-are-versioned-bilingual-artefacts.md) prompts.
- **Interface** — [0035](0035-inline-keyboards-for-choices-never-for-capture.md)
  buttons in chat, [0036](0036-undo-is-a-first-class-action.md) undo,
  [0037](0037-keyboard-first-on-desktop.md) the keyboard model,
  [0007](0007-household-app-nextjs-over-postgrest-edited-with-onlook.md)
  the household app, [0014](0014-postgrest-and-row-level-security-as-the-data-api.md)
  PostgREST and row-level security,
  [0022](0022-design-system.md) the design system,
  [0017](0017-russian-and-english-with-language-neutral-domain-data.md) languages.
- **People and access** — [0005](0030-identity-is-ours-telegram-is-a-linked-channel.md)
  membership, [0016](0016-permissions-everyone-reads-admins-edit.md) permissions,
  [0006](0032-sign-in-methods-password-passkeys-and-apple.md) web access,
  [0026](0026-membership-lifecycle-and-departure.md) departure.
- **Operations** — [0009](0009-backups-encrypted-offsite-with-tested-restore.md)
  backups, [0024](0024-secret-custody-and-recovery.md) secret custody,
  [0020](0020-monitoring-with-heartbeats-and-telegram-alerts.md) monitoring,
  [0010](0010-configuration-as-code.md) configuration as code,
  [0015](0015-verification-strategy.md) verification.

If you read four, read 0011, 0014, 0016 and 0024: the books, the boundary, who
may change what, and why the household does not lose everything when one person
is unavailable.

### What rests on what

Foundations first — these are the decisions others are written against:

| Decision | Carries |
|---|---|
| [0004](0004-postgresql-as-system-of-record.md) PostgreSQL is the system of record | 0008 audit, 0011 ledger, 0012 forecast, 0014 API, 0018 migrations, 0019 files, 0021 projects |
| [0011](0011-double-entry-ledger-and-chart-of-accounts.md) Double-entry | 0012, 0013, 0021, 0023 — and every report |
| [0027](0027-telegram-as-the-conversational-platform.md) Telegram | 0005 identity, 0001 workflows, 0020 alerting |
| [0002](0002-self-hosted-docker-compose-topology.md) Compose and portability | every component's deployment, 0009 backups |
| [0014](0014-postgrest-and-row-level-security-as-the-data-api.md) PostgREST and row-level security | 0007 the app, 0016 permissions in practice, 0015 what the tests prove |

Two exceptions to self-hosting, both deliberate and both in the capture path:
[0029](0029-model-gateway-and-per-task-routing.md) the model gateway, and
[0027](0027-telegram-as-the-conversational-platform.md) Telegram. Nothing else
leaves the household.

## When an ADR is needed

- choice of platform, language, storage, deployment model;
- a decision that would be expensive to reverse;
- a decision someone will question in six months without knowing the context.

Decisions scoped to a single feature live in that feature's `plan.md`.

## Register

| # | Decision | Status | Date |
|---|---|---|---|
| [0001](0001-n8n-as-automation-platform.md) | n8n as the automation and agent platform | accepted | 2026-09-12 |
| [0002](0002-self-hosted-docker-compose-topology.md) | Docker Compose on a cheap VPS, portable to a home server | accepted | 2026-09-12 |
| [0003](0003-openrouter-as-model-gateway.md) | OpenRouter as the single model gateway | superseded by [0029](0029-model-gateway-and-per-task-routing.md) | 2026-09-12 |
| [0004](0004-postgresql-as-system-of-record.md) | PostgreSQL as the system of record | accepted | 2026-09-12 |
| [0005](0005-household-membership-via-telegram-allowlist.md) | Household membership via a Telegram allow-list | superseded by [0030](0030-identity-is-ours-telegram-is-a-linked-channel.md) | 2026-09-12 |
| [0006](0006-admin-access-via-authentik-and-passkeys.md) | Web access via a self-hosted IdP, passkeys and Apple sign-in | superseded by [0032](0032-sign-in-methods-password-passkeys-and-apple.md) | 2026-09-12 |
| [0007](0007-household-app-nextjs-over-postgrest-edited-with-onlook.md) | Household app: a small Next.js app over PostgREST, edited visually with Onlook | accepted | 2026-09-12 |
| [0008](0008-append-only-audit-log-in-postgresql.md) | Append-only audit log in PostgreSQL, enforced by triggers | accepted | 2026-09-12 |
| [0009](0009-backups-encrypted-offsite-with-tested-restore.md) | Nightly encrypted offsite backups, restore verified on a schedule | accepted | 2026-09-12 |
| [0010](0010-configuration-as-code.md) | All tool configuration exported and committed to this repository | accepted | 2026-09-12 |
| [0011](0011-double-entry-ledger-and-chart-of-accounts.md) | Double-entry ledger with a chart of accounts; cards, overdraft, loans | accepted | 2026-09-12 |
| [0012](0012-plans-budgets-and-commitments-are-not-postings.md) | Budgets, commitments and planned purchases are forecast objects, not postings | accepted | 2026-09-12 |
| [0013](0013-statement-ingestion-structured-first-pdf-via-model.md) | Statement ingestion: structured formats first, PDF through the model | accepted | 2026-09-12 |
| [0014](0014-postgrest-and-row-level-security-as-the-data-api.md) | PostgREST over the SQL views as the data API, authorisation in RLS | accepted | 2026-09-12 |
| [0015](0015-verification-strategy.md) | Verification strategy: tests against a real database, ranked by risk | accepted | 2026-09-12 |
| [0016](0016-permissions-everyone-reads-admins-edit.md) | Everyone reads the whole ledger; only an admin edits what is recorded | accepted | 2026-09-12 |
| [0017](0017-russian-and-english-with-language-neutral-domain-data.md) | Russian and English, with domain data stored language-neutral | accepted | 2026-09-12 |
| [0018](0018-dbmate-for-migrations.md) | dbmate for migrations, with the dumped schema as a reviewed artefact | accepted | 2026-09-12 |
| [0019](0019-content-addressed-file-storage-on-a-volume.md) | Receipts and statements as content-addressed files on a volume | accepted | 2026-09-12 |
| [0020](0020-monitoring-with-heartbeats-and-telegram-alerts.md) | Monitoring: heartbeats and health checks in Uptime Kuma, alerts to Telegram | accepted | 2026-09-12 |
| [0021](0021-projects-and-wishlist.md) | Projects as a second reporting axis; the wishlist is what has no date yet | accepted | 2026-09-12 |
| [0022](0022-design-system.md) | Design system: tokens, shadcn/ui on Radix, and the data-viz method as a standard | accepted | 2026-09-12 |
| [0023](0023-human-confirmation-of-model-derived-records.md) | Model-derived records are unconfirmed until a human or the bank confirms them | accepted | 2026-09-12 |
| [0024](0024-secret-custody-and-recovery.md) | Every secret has two custodians, and recovery is rehearsed | accepted | 2026-09-12 |
| [0025](0025-prompts-are-versioned-bilingual-artefacts.md) | Prompts are versioned bilingual artefacts, gated by the golden set | accepted | 2026-09-12 |
| [0026](0026-membership-lifecycle-and-departure.md) | Membership changes are designed; a departure does not rewrite the books | accepted | 2026-09-12 |
| [0027](0027-telegram-as-the-conversational-platform.md) | Telegram is the conversational platform, and the source of member identity | accepted | 2026-09-12 |
| [0028](0028-eu-data-residency-as-a-direction.md) | EU data residency is the direction, with the data stores there from the start | accepted | 2026-09-12 |
| [0029](0029-model-gateway-and-per-task-routing.md) | OpenRouter with a model per task, spend capped, and a residency ladder | accepted | 2026-09-12 |
| [0030](0030-identity-is-ours-telegram-is-a-linked-channel.md) | A member is an account of ours; Telegram is a channel linked by an admin | accepted | 2026-09-12 |
| [0031](0031-chart-of-accounts-and-categories-are-admin-managed.md) | The chart of accounts is editable data, by an admin and by the agent | accepted | 2026-09-12 |
| [0032](0032-sign-in-methods-password-passkeys-and-apple.md) | Three sign-in methods: email and password, passkeys, and Apple linked later | accepted | 2026-09-12 |
| [0033](0033-telegram-updates-by-webhook-and-polling.md) | Telegram updates by webhook when deployed, long polling locally | accepted | 2026-09-12 |
| [0034](0034-settings-live-in-env-or-in-data-never-in-code.md) | Deployment settings in env, household settings in data, nothing hard-coded | accepted | 2026-09-12 |
| [0035](0035-inline-keyboards-for-choices-never-for-capture.md) | Inline buttons for choices and confirmations, never for capture | accepted | 2026-09-12 |
| [0036](0036-undo-is-a-first-class-action.md) | Undo is a first-class action, scoped to the actor and audited | accepted | 2026-09-12 |
| [0037](0037-keyboard-first-on-desktop.md) | Keyboard-first on desktop: a command palette, single-key actions, no mouse-only path | accepted | 2026-09-12 |
| [0038](0038-conversation-state-lives-in-the-database.md) | Conversation state lives in PostgreSQL, never in the workflow engine | accepted | 2026-09-12 |
| [0039](0039-the-agents-tools-are-a-declared-contract.md) | The agent's tools are a declared, validated contract in this repository | accepted | 2026-09-12 |
| [0040](0040-workflows-are-small-named-and-composed.md) | Workflows are small, named by what they do, and composed rather than branched | accepted | 2026-09-12 |
| [0041](0041-forward-auth-token-bridge.md) | Authentik authenticates the session; a token bridge mints the PostgREST JWT | accepted | 2026-09-12 |
| [0042](0042-a-tool-call-runs-as-the-acting-identity.md) | A tool call writes as the member it acts for, never as the agent alone | accepted | 2026-09-13 |
| [0043](0043-a-shared-group-chat-alongside-private-ones.md) | A member may message the bot privately or from one shared household group | accepted | 2026-09-13 |
| [0044](0044-the-agent-keeps-its-own-memory.md) | The agent keeps its own memory, separate from the ledger and from conversation state | accepted | 2026-09-13 |
