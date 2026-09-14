# Implementation plan

Eleven slices, in order, with the documentation that goes with each. This is the
**sequencing** document: once a slice starts it gets its own `plan.md` and
`tasks.md` (`/spec-plan`, `/spec-tasks`), and those are authoritative for how it
is built. This says what comes when, what each phase delivers, and what must be
true before the next one starts.

Two rules run through all of it:

- **Local first, always.** Every phase is built and verified on a laptop, with no
  domain, no tunnel and nothing purchased, against the seeded household. Deploying
  is a separate, later step in phase 1 and never a prerequisite for building.
- **A phase is done when its criteria are closed by named tests** (ADR 0015), and
  the workflow and app exports are committed (ADR 0010). Not when it appears to
  work.

---

## Phase 0 — Repository scaffolding

Before any slice: the skeleton everything else is added to. A day's work, and it
is what makes every later phase a small change rather than a setup.

1. `Taskfile.yml` with the commands every later phase invokes: `up`, `down`,
   `migrate`, `seed`, `test`, `export`, `backup`, `restore`, `scaffold-admin`.
   Same commands locally and in CI (ADR 0034).
2. `.env.example` — every variable by name, no values, grouped by component.
   It grows with each phase and is the deployment's inventory.
3. `compose.yaml` with PostgreSQL only, plus a `local` profile. Other services
   join it as their phase arrives.
4. `dbmate` wired up: `db/migrations/`, the committed `db/schema.sql` dump, and a
   migration container that runs before dependants (ADR 0018).
5. GitHub Actions: a PostgreSQL service, `task migrate`, `task test`. Red on a
   broken migration from the first commit.
6. `docs/guides/local-development.md` — first version: prerequisites, `task up`,
   what runs, how to get a shell. It is extended by every phase, and a phase is
   not done until it is.

**Delivers:** a checkout that comes up, migrates and runs an empty test suite.

---

## Phase 1 — Infrastructure bootstrap (spec 0001)

1. **Test harness first**, before anything to test: pgTAP installed in the test
   database, a `task test` that creates a throwaway database, migrates, seeds and
   runs. Writing this first is what makes every later criterion closable.
2. **Seed script** — the synthetic household: three members, account *shapes*,
   several months of transactions including a card settlement, a cash-advance fee,
   overdraft interest and a loan payment split (ADR 0015). It is fixture, demo and
   development data at once.
3. **The file volume**: content-addressed storage by SHA-256, the metadata table,
   and the integrity job that re-hashes and reports (ADR 0019).
4. **n8n** in Compose, with its encryption key in the environment, a health-check
   workflow, and the export/import tasks. Prove the export round-trips before
   there is anything worth exporting.
5. **Telegram delivery, both modes** (ADR 0033): the normalisation step, the
   polling mode for local, the webhook mode for deployed, the local bot
   registration, and idempotency on re-delivery.
6. **Monitoring**: Uptime Kuma, health checks for each service, and a heartbeat
   for every scheduled job — verified by stopping a job and receiving the alert
   (ADR 0020).
7. **Backups**: restic to a local repository first, then the EU offsite one; the
   nightly job, the retention policy, and the monthly verification restore with
   its heartbeat (ADR 0009).
8. **Configuration as code**: the export task for n8n, drift detection on a
   schedule, and the report to Telegram (ADR 0010).
9. **The message catalogue** for Russian and English, loaded by the components,
   failing visibly on a missing string (ADR 0017).
10. **`scaffold-admin`**: creates the first admin from the environment, refuses
    once any account exists, marks the password as initial (spec 0002, R14a).
11. **Rate limiting** at the edge on public surfaces.
12. **Documentation**: `docs/guides/local-development.md` completed for real — a
    new machine to a running system in one page. `docs/guides/operations.md`
    started: the secret inventory, the backup and restore procedure, what each
    alert means.

**Delivers:** the system runs locally, backs itself up, restores, reports its own
failures, and can be rebuilt from the repository.
**Gate before phase 2:** the restore verification has passed once, unattended.

---

## Phase 2 — Identity and access (spec 0002)

1. **authentik** in Compose, configured **only** through blueprints (ADR 0010),
   running locally as it does when deployed (R17c).
2. **The reverse proxy as the boundary**: forward authentication in front of every
   surface, and each container's own port unreachable from outside.
3. **Members and links**: the `members` table with our own identifier, and link
   tables for the provider subject and the Telegram id (ADR 0030).
4. **Email and password sign-in** end to end, then the scaffolded admin changing
   its initial password (ADR 0032).
5. **Passkey enrolment** — on `localhost`, which is a secure context, so this is
   testable before any domain exists.
6. **Roles and row-level security**: the six database roles, default-deny on
   every table, and the acting-member requirement that makes a write without an
   actor fail (spec 0002, R15b–R15c).
7. **PostgREST** with the token path: the member id templated into the claim, the
   proxy adding the Authorization header so the browser never holds a token
   (R15a, R16a).
8. **The impersonation test suite** — the highest-value tests in the project
   (ADR 0015): a member cannot edit, cannot delete, cannot insert a posting;
   anonymous reads nothing; a tampered or expired token is refused.
9. **Channel linking**: the one-time code flow, an admin confirming, and an
   unlinked id reaching nothing.
10. **Break-glass**: SSH keys for both admins, the provider console path, both
    documented and tried once.
11. **Apple sign-in** — only if the membership exists. Otherwise skipped without
    blocking anything, and added later as a link.
12. **Documentation**: the identity section of `operations.md` — how to add a
    member, link a channel, reset a password, revoke a device, get in when
    authentik is down.

**Delivers:** every surface behind one sign-in, and authorisation proven at the
database by impersonation.
**Gate before phase 3:** the negative tests pass. Nothing else in the project is
allowed to depend on a permission that has not been tested this way.

---

## Phase 3 — The books and text capture (spec 0003)

This is the phase that makes it a product. Largest of the eleven; build it in
this order and each step is verifiable on its own.

1. **The schema, in migrations**, from
   [data-model.md](architecture/data-model.md): account types and accounts,
   transactions and postings, members and their links, merchants and aliases,
   translations, captures, files, the **conversation** table (ADR 0038), and the
   audit tables.
2. **The invariant**: postings sum to zero, enforced by a deferred constraint or
   trigger — and its pgTAP test, written by attacking it directly.
3. **The audit triggers**: before and after images, the actor from the
   transaction, immutability for application roles (ADR 0008).
4. **Balances and the first views**, derived from postings, never stored.
5. **The setup conversation** (R0): the agent asking for accounts, opening
   balances, default payment accounts, cash handling, timezone and currency —
   resumable, and useful after the first account.
6. **Structural changes through the agent**: open, rename, deactivate, re-term an
   account; rename, re-parent, merge a category — each restated and confirmed,
   each audited to the asking admin (ADR 0031).
6a. **The tool registry** (ADR 0039): declarations, input schemas, permissions,
    and the negative tests that prove the wrong member cannot call one.
7. **The capture workflow**: prompt and schema from the mounted repository, the
   model call through the gateway, schema validation, the merchant registry
   consulted before any model, defaults for the account and the date.
8. **Confirmation state** (ADR 0023): unconfirmed on creation, the member's own
   window, the conservative auto-confirm, and the chat command that lists and
   confirms.
9. **Corrections and the request path**: an admin corrects; a member asks and the
   admins are notified.
10. **Unparsed captures**: stored, one question asked, resumable.
11. **The golden set** and its first run, recorded (ADR 0025).
11a. **The conveniences that make it pleasant**, and they are not optional
    polish: inline buttons on the confirmation, "undo", notes on a transaction,
    "как обычно" to repeat the last expense at a merchant, the recent list, the
    original currency stored alongside the charged amount, and "what still needs
    setting up" (ADRs 0035, 0036). Each is small; together they are the
    difference between a system that is used and one that is abandoned.
12. **Documentation**: `docs/guides/household-setup.md` — what the setup
    conversation asks and why, so an admin knows what to have to hand. And the
    first user-facing page: what you can say to Meow.

**Delivers:** a member writes "coffee 350" and the household's books gain a
correct, attributed, balanced transaction.
**Gate before phase 4:** a week of real captures by more than one person, locally
or deployed. If capture is not pleasant, nothing built on top of it matters.

### Deploying for the first time

Between phases 3 and 4, and not before: the household cannot use a laptop.

1. Answer the seven startup questions (specs 0001 and 0002).
2. Provision the EU host, the domain, the certificate, the offsite repository.
3. Run the same `task up` with a deployed `.env`; switch Telegram to webhook mode.
4. Scaffold the admin, enrol both admins, link the channels.
5. Run the setup conversation for real, with the household's actual accounts.
6. Confirm one backup and one verification have run.
7. **Documentation:** `docs/guides/deployment.md`, written **while** doing it —
   the only time it is accurate.

---

## Phase 4 — Reading the books (spec 0004)

1. The reporting views from
   [data-model.md](architecture/data-model.md)'s catalogue: totals, by category,
   by merchant, by member, period comparison, unconfirmed share — with their
   signatures snapshotted from the first migration.
2. The read tools over those views, and **the agent's tool-calling loop**
   (ADR 0046) — one prompt, one loop, the tools doing the database work. Spec
   0003's per-task prompts and workflows are migrated onto it and deleted.
3. Answers the agent writes itself, in the member's language, every figure with
   its period and traceable to the tool result it came from.
4. The weekly and monthly digests, their schedules, their heartbeats, and the
   per-member opt-out.
4a. **Search** over notes, merchants and captures; **"why this category"**; and
   **CSV export** of a period — the last of which is what makes the books
   credibly the household's own.
5. **Documentation**: the list of questions the bot can answer, kept current — it
   is the contract, and a question outside it is a refusal by design.

**Delivers:** the books answer, and arrive uninvited once a week.

---

## Phase 5 — Photos and voice (spec 0005)

1. **First task, before anything else:** verify that audio reaches the chosen
   model through the gateway, and record which fallback is needed if not
   (ADR 0029).
2. Receipt prompt and schema; voice prompt and schema; both separate from text.
3. File storage and linking, reusing phase 1's content-addressed store.
4. Line items stored when returned; transcripts into the audit record.
5. The cost ceiling per task, with the "type it instead" fallback.
6. Multi-page handling, captions as hints, and the never-auto-confirm rule.
7. Golden-set entries for both, with scores recorded.

**Delivers:** the fastest capture in the product needs no words.

---

## Phase 6 — The household app (spec 0006)

1. Next.js and Tailwind scaffold, the design tokens, and the shadcn components
   copied in (ADR 0022).
2. The PostgREST client against relative paths — no token in the page.
3. **Home screen**: balances, month to date, unconfirmed count and its entry
   point — laid out in [design/screens.md](design/screens.md), which names the
   views phase 4 must have produced.
4. **Category screen** with its trend, then merchant, then member (R22).
5. The confirmation queue: batch approval and inline correction.
6. Merchant merging.
7. Every state: empty-because-new, empty-because-filtered, loading, error,
   provisional, not-permitted.
8. Both languages checked at their longest strings; light and dark; 390 px.
9. **The keyboard model** (ADR 0037): the command registry, the focus model, the
   palette, the `?` map, and single-key actions on every list. Built with the
   screens rather than after them — retrofitting a focus model is a rewrite.
10. Playwright journeys at phone viewport **and a keyboard-only pass on desktop**,
   run rather than reasoned about.
11. The static build in CI, served by the proxy behind the boundary.
12. **Onlook**: the household's admin opens the app in it and adjusts appearance.
    Whatever comes out is a commit like any other.
13. **Documentation**: `docs/guides/ui-editing.md` — how to change how it looks
    without touching logic, for the admin who will actually do it.

**Delivers:** the screen a household member asked for, and the queue stops being
a chore.

---

## Phase 7 — Statements and reconciliation (spec 0007)

1. **First task:** obtain one real export per provider, anonymise it, commit it
   as a fixture (R25).
2. The normalised statement-line model and the import batch.
3. Parsers: CAMT.053, then CSV for ICS, then MT940, then XLS — each against its
   fixture.
4. The closing-balance check, and the alternative validation for formats without
   one (R9a).
5. Matching: references, amount and date tolerance, the duplicate case, the
   ambiguous case flagged rather than guessed.
6. Card settlement as a transfer; interest and fees to their own accounts.
7. Confirmation by the bank, which is what drains the queue.
8. Provisional PDF lines, and their supersession by a later structured import.
9. Preview, then apply, then reversal as one audited unit.
10. The reconciliation review screen in the app.
11. **Documentation**: `docs/guides/monthly-routine.md` — three downloads, three
    uploads, what to do with what it flags. The household's only recurring chore,
    written down.

**Delivers:** the books stop being what anyone remembered.

---

## Phase 8 — Borrowing (spec 0008)

1. Terms on liability accounts, with effective dates.
2. The amortisation schedule as a forecast object — and the test that it creates
   no postings.
3. The payment split, and re-derivation from actuals.
4. Cash-advance fees as their own posting.
5. Cost-of-credit and liability views; overdraft headroom.
6. The limit alert at 80%, and the missed-payment surface.

**Delivers:** what credit costs, as a number rather than a feeling.

---

## Phase 9 — Budgets, commitments and the forecast (spec 0009)

1. Commitments first — they are the load-bearing half — collected by the agent,
   including income.
2. Matching commitments through the same machinery as statement lines.
3. Missed commitments as a first-class state.
4. The projection views: balances plus commitments over the horizon, derived on
   every read.
5. The affordability question in chat, stating its assumptions.
6. Budgets with rollover, and progress against elapsed time.
7. The four alerts, each once per condition, to the admins.
8. The per-member "what is left" view.

**Delivers:** the month ahead, not only the month behind.

---

## Phase 10 — Wishes and projects (spec 0010)

1. Wishes: added in one message, outside the forecast, promotable by a date.
2. Projects with states and targets; the project reference on transactions.
3. Project reports across categories and periods.
4. Feasibility and the monthly set-aside, from known commitments only.
5. The belongs-to-a-project question, above its threshold, asked and never
   assumed.
6. Affordability ordering of the wishlist.

**Delivers:** "what did the holiday cost" and "can we have the deposit by March".

---

## Phase 11 — Moving home (spec 0011)

1. Provision the home server; no product change in this phase.
2. Carry the data; cut over; verify balances, row counts and file hashes.
3. Monitoring and backups from the new location; first verification passed.
4. **The rehearsal that is the point:** the second admin restores alone, from the
   sealed copy and the written procedure. Every improvised step is a defect in the
   procedure, fixed and repeated.
5. The rebuild demonstration on an empty host.
6. One month of correct operation, then decommission the rented host.
7. Re-state ADR 0028's gap table with what the move closed.
8. **Documentation**: `operations.md` and `deployment.md` updated by what the
   rehearsal exposed — the only reliable source of what a procedure is missing.

**Delivers:** the household's financial system on its own hardware, with recovery
proven by someone who did not build it.

---

## The documentation track

Documentation is part of each phase, not a phase of its own. What exists when:

| Document | Written in | Kept current by |
|---|---|---|
| `guides/local-development.md` | Phase 0, completed phase 1 | Every phase that adds a component |
| `guides/operations.md` | Phase 1, extended phase 2 | Phases 7 and 11 |
| `guides/household-setup.md` | Phase 3 | Phases 8 and 9, which add what setup collects |
| `guides/deployment.md` | The first deployment, while doing it | Phase 11 |
| `guides/talking-to-meow.md` | Phase 3, extended each capture phase | Phases 4, 5, 8, 9, 10 — every slice that adds a view adds its questions |
| `guides/monthly-routine.md` | Phase 7 | Phase 8 |
| `guides/ui-editing.md` | Phase 6 | When Onlook's behaviour changes |
| `README.md` quickstart | Phase 1 | Whenever the first command changes |

A phase whose guide is not updated is not done. The reason is narrow and
practical: the household has two admins, and the one who did not build a thing is
the one who will need it at the worst moment.

## What is deliberately not parallelised

- **Identity before anything that stores household data.** Building capture
  before authorisation means retrofitting row-level security onto live books.
- **Capture before reading.** A report over three test rows teaches nothing.
- **Reading before the app.** The views are the app; without them the app is a
  place to put numbers that do not exist yet.
- **Statements after the app.** Reconciliation's output needs somewhere to be
  reviewed, and its flags need a screen.
- **The move home last.** It proves claims the earlier phases make; proving them
  before they are made is not possible.

The exception: **documentation is never deferred to a later phase.** It is the one
thing that cannot be caught up on, because what made it worth writing is
forgotten by then.
