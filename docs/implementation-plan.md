# Implementation plan

Here we sequence the eleven slices and name the documentation that goes with
each. Once a slice starts it gets its own `plan.md` and `tasks.md` through
`/spec-plan` and `/spec-tasks`, and those two are authoritative for how the
slice is built. This page says what comes when, what each phase delivers, and
what has to be true before the next one starts.

Two rules run through all of it:

- We build locally first, always. Every phase is built and verified on a laptop
  against the seeded household, with no domain, no tunnel and nothing purchased.
  Deploying is a separate, later step inside phase 1, and no phase ever needs it
  to start.
- A phase is done when named tests close its criteria (ADR 0015) and the
  workflow and app exports are committed (ADR 0010), and not when it looks like
  it works.

---

## Phase 0 - Repository scaffolding

Phase 0 builds the skeleton every later phase adds to. It takes a day, and it is
what turns each later phase into a small change instead of a fresh setup.

1. `Taskfile.yml` with the commands every later phase invokes: `up`, `down`,
   `migrate`, `seed`, `test`, `export`, `backup`, `restore`, `scaffold-admin`.
   The same commands run locally and in CI (ADR 0034).
2. `.env.example` naming every variable, with no values, grouped by component.
   It grows with each phase, and it is the deployment's inventory.
3. `compose.yaml` with PostgreSQL only, plus a `local` profile. The other
   services join it as their phase arrives.
4. `dbmate` wired up: `db/migrations/`, the committed `db/schema.sql` dump, and a
   migration container that runs before anything that depends on it (ADR 0018).
5. GitHub Actions: a PostgreSQL service, `task migrate`, `task test`. A broken
   migration turns CI red from the first commit.
6. The first version of `docs/guides/local-development.md`: prerequisites,
   `task up`, what runs, and how to get a shell. Every phase extends it, and no
   phase is done until it has.

Delivers: a checkout that comes up, migrates and runs an empty test suite.

---

## Phase 1 - Infrastructure bootstrap (spec 0001)

1. Build the test harness before there is anything to test: pgTAP installed in
   the test database, and a `task test` that creates a throwaway database,
   migrates, seeds and runs. Writing it first is what makes every later
   criterion closable.
2. Write the seed script for the synthetic household: three members, account
   shapes, and several months of transactions including a card settlement, a
   cash-advance fee, overdraft interest and a loan payment split (ADR 0015). It
   serves as fixture, demo and development data at once.
3. Build the file volume: content-addressed storage by SHA-256, the metadata
   table, and the integrity job that re-hashes and reports (ADR 0019).
4. Add n8n to Compose, with its encryption key in the environment, a
   health-check workflow, and the export and import tasks. Prove the export
   round-trips before there is anything worth exporting.
5. Build Telegram delivery in both modes (ADR 0033): the normalisation step,
   polling for local, webhooks for deployed, the local bot registration, and
   idempotency on re-delivery.
6. Add monitoring: Uptime Kuma, a health check for each service, and a heartbeat
   for every scheduled job, verified by stopping a job and receiving the alert
   (ADR 0020).
7. Set up backups: restic to a local repository first, then the EU offsite one,
   with the nightly job, the retention policy, and the monthly verification
   restore and its heartbeat (ADR 0009).
8. Put the configuration in code: the export task for n8n, drift detection on a
   schedule, and the report to Telegram (ADR 0010).
9. Add the message catalogue for Russian and English, loaded by the components
   and failing visibly on a missing string (ADR 0017).
10. Write `scaffold-admin`, which creates the first admin from the environment,
    refuses once any account exists, and marks the password as initial (spec
    0002, R14a).
11. Rate-limit the public surfaces at the edge.
12. Finish `docs/guides/local-development.md` for real, so that one page takes a
    new machine to a running system. Start `docs/guides/operations.md` with the
    secret inventory, the backup and restore procedure, and what each alert
    means.

Delivers: the system runs locally, backs itself up, restores, reports its own
failures, and can be rebuilt from the repository.
Gate before phase 2: the restore verification has passed once, unattended.

---

## Phase 2 - Identity and access (spec 0002)

1. Add authentik to Compose, configured only through blueprints (ADR 0010), and
   running locally the same way it runs deployed (R17c).
2. Make the reverse proxy the boundary: forward authentication in front of every
   surface, and no container's own port reachable from outside.
3. Create members and links: the `members` table with our own identifier, and
   link tables for the provider subject and the Telegram id (ADR 0030).
4. Get email and password sign-in working end to end, then have the scaffolded
   admin change its initial password (ADR 0032).
5. Enrol a passkey on `localhost`, which is a secure context, so you can test
   this before any domain exists.
6. Add roles and row-level security: the six database roles, default-deny on
   every table, and the acting-member requirement that makes a write without an
   actor fail (spec 0002, R15b to R15c).
7. Wire PostgREST to the token path: the member id templated into the claim, and
   the proxy adding the Authorization header so the browser never holds a token
   (R15a, R16a).
8. Write the impersonation test suite, which carries more value than any other
   tests in the project (ADR 0015): a member cannot edit, cannot delete and
   cannot insert a posting, anonymous reads nothing, and a tampered or expired
   token is refused.
9. Build channel linking: the one-time code flow, an admin confirming it, and an
   unlinked id reaching nothing.
10. Prepare break-glass access: SSH keys for both admins and the provider
    console path, both documented and tried once.
11. Add Apple sign-in, but only if the membership exists. Otherwise skip it, let
    nothing block on it, and add it later as a link.
12. Write the identity section of `operations.md`: how to add a member, link a
    channel, reset a password, revoke a device, and get in when authentik is
    down.

Delivers: every surface behind one sign-in, with authorisation proven at the
database by impersonation.
Gate before phase 3: the negative tests pass. Nothing else in the project can
depend on a permission that has not been tested this way.

---

## Phase 3 - The books and text capture (spec 0003)

Phase 3 turns the system into a product, and it is the largest of the eleven.
Build it in the order below and you can verify each step on its own.

1. Write the schema in migrations, from
   [data-model.md](architecture/data-model.md): account types and accounts,
   transactions and postings, members and their links, merchants and aliases,
   translations, captures, files, the `conversation` table (ADR 0038), and the
   audit tables.
2. Enforce the invariant that postings sum to zero, with a deferred constraint or
   a trigger, and write its pgTAP test by attacking the constraint directly.
3. Add the audit triggers: before and after images, the actor from the
   transaction, and immutability for application roles (ADR 0008).
4. Derive balances and the first views from postings, and store neither.
5. Build the setup conversation (R0), where the agent asks for accounts, opening
   balances, default payment accounts, cash handling, timezone and currency. It
   resumes after an interruption, and it is useful from the first account
   onwards.
6. Let an admin make structural changes through the agent: open, rename,
   deactivate and re-term an account, and rename, re-parent and merge a
   category. The agent restates and confirms each one, and audits it to the
   admin who asked (ADR 0031).
6a. Build the tool registry (ADR 0039): declarations, input schemas, permissions,
    and the negative tests that prove the wrong member cannot call a tool.
7. Build the capture workflow: prompt and schema from the mounted repository,
   the model call through the gateway, schema validation, the merchant registry
   consulted before any model runs, and defaults for the account and the date.
8. Add confirmation state (ADR 0023): unconfirmed on creation, the member's own
   window, the conservative auto-confirm, and the chat command that lists and
   confirms.
9. Build corrections and the request path, so that an admin corrects directly
   and a member asks, which notifies the admins.
10. Store unparsed captures, ask one question about them, and let the exchange
    resume later.
11. Assemble the golden set and record its first run (ADR 0025).
11a. Build the conveniences that make capture pleasant, which are not optional
    polish: inline buttons on the confirmation, "undo", notes on a transaction,
    "как обычно" to repeat the last expense at a merchant, the recent list, the
    original currency stored alongside the charged amount, and "what still needs
    setting up" (ADRs 0035, 0036). Each one is small, and together they decide
    whether the household uses the system or abandons it.
12. Write `docs/guides/household-setup.md` on what the setup conversation asks
    and why, so an admin knows what to have to hand. Write the first
    user-facing page too: what you can say to Meow.

Delivers: a member writes "coffee 350" and the household's books gain a correct,
attributed, balanced transaction.
Gate before phase 4: a week of real captures by more than one person, locally or
deployed. If capture is not pleasant, nothing built on top of it matters.

### Deploying for the first time

Deploy between phases 3 and 4 and not before, because the household cannot use a
laptop.

1. Answer the seven startup questions (specs 0001 and 0002).
2. Provision the EU host, the domain, the certificate, and the offsite
   repository.
3. Run the same `task up` with a deployed `.env`, and switch Telegram to webhook
   mode.
4. Scaffold the admin, enrol both admins, and link the channels.
5. Run the setup conversation for real, with the household's actual accounts.
6. Confirm that one backup and one verification have run.
7. Write `docs/guides/deployment.md` while you deploy, because that is the only
   time it comes out accurate.

---

## Phase 4 - Reading the books (spec 0004)

1. Build the reporting views from the catalogue in
   [data-model.md](architecture/data-model.md): totals, by category, by
   merchant, by member, period comparison, and unconfirmed share, with their
   signatures snapshotted from the first migration.
2. Build the read tools over those views and the agent's tool-calling loop
   (ADR 0046): one prompt, one loop, and the tools doing the database work.
   Migrate spec 0003's per-task prompts and workflows onto it, then delete them.
3. Have the agent write its own answers, in the member's language, with every
   figure carrying its period and traceable to the tool result it came from.
4. Add the weekly and monthly digests, their schedules, their heartbeats, and the
   per-member opt-out.
4a. Add search over notes, merchants and captures, the "why this category"
   answer, and CSV export of a period. The export is what makes the books
   credibly the household's own.
5. Write the list of questions the bot can answer and keep it current. That list
   is the contract, and a question outside it gets a refusal by design.

Delivers: the books answer, and arrive uninvited once a week.

---

## Phase 5 - Photos and voice (spec 0005)

1. Before anything else, check that audio reaches the chosen model through the
   gateway, and record which fallback you need if it does not (ADR 0029).
2. Write the receipt prompt and schema and the voice prompt and schema, both
   separate from text.
3. Store and link files, reusing phase 1's content-addressed store.
4. Store line items when the model returns them, and transcripts into the audit
   record.
5. Add the cost ceiling per task, with the "type it instead" fallback.
6. Handle multi-page documents, take captions as hints, and never auto-confirm.
7. Add golden-set entries for both paths, and record their scores.

Delivers: the fastest capture in the product needs no words.

---

## Phase 6 - The household app (spec 0006)

1. Scaffold Next.js and Tailwind, add the design tokens, and copy in the shadcn
   components (ADR 0022).
2. Point the PostgREST client at relative paths, with no token in the page.
3. Build the home screen: balances, month to date, and the unconfirmed count
   with its entry point, laid out in [design/screens.md](design/screens.md),
   which names the views phase 4 must have produced.
4. Build the category screen with its trend, then merchant, then member (R22).
5. Build the confirmation queue with batch approval and inline correction.
6. Add merchant merging.
7. Draw every state: empty because new, empty because filtered, loading, error,
   provisional, and not permitted.
8. Check both languages at their longest strings, in light and dark, at 390 px.
9. Build the keyboard model (ADR 0037): the command registry, the focus model,
   the palette, the `?` map, and single-key actions on every list. Build it with
   the screens and not after them, because retrofitting a focus model means
   rewriting them.
10. Run the Playwright journeys at phone viewport and a keyboard-only pass on
   desktop, instead of reasoning about what they would do.
11. Produce the static build in CI, served by the proxy behind the boundary.
12. Have the household's admin open the app in Onlook and adjust its appearance.
    Whatever comes out is a commit like any other.
13. Write `docs/guides/ui-editing.md` on how to change how the app looks without
    touching logic, for the admin who will actually do it.

Delivers: the screen a household member asked for, and a queue that stops being a
chore.

---

## Phase 7 - Statements and reconciliation (spec 0007)

1. First, obtain one real export per provider, anonymise it, and commit it as a
   fixture (R25).
2. Build the normalised statement-line model and the import batch.
3. Write the parsers in this order, each against its fixture: CAMT.053, then CSV
   for ICS, then MT940, then XLS.
4. Add the closing-balance check, and the alternative validation for formats
   that have no closing balance (R9a).
5. Build matching on references, amount and date tolerance, the duplicate case,
   and the ambiguous case, which you flag instead of guessing.
6. Record a card settlement as a transfer, and interest and fees to their own
   accounts.
7. Add confirmation by the bank, which is what drains the queue.
8. Mark PDF lines provisional, and supersede them from a later structured
   import.
9. Make preview, apply and reversal one audited unit.
10. Build the reconciliation review screen in the app.
11. Write `docs/guides/monthly-routine.md`: three downloads, three uploads, and
    what to do with what the import flags. It is the household's only recurring
    chore, and it deserves to be written down.

Delivers: the books stop being what anyone remembered.

---

## Phase 8 - Borrowing (spec 0008)

1. Put terms on liability accounts, with effective dates.
2. Build the amortisation schedule as a forecast object, and write the test that
   it creates no postings.
3. Build the payment split, and re-derive it from actuals.
4. Post cash-advance fees to their own posting.
5. Build the cost-of-credit and liability views, and overdraft headroom.
6. Add the limit alert at 80%, and the missed-payment surface.

Delivers: what credit costs, as a number instead of a feeling.

---

## Phase 9 - Budgets, commitments and the forecast (spec 0009)

1. Start with commitments, which carry the weight of this slice, collected by
   the agent and including income.
2. Match commitments through the same machinery as statement lines.
3. Make a missed commitment a first-class state.
4. Build the projection views: balances plus commitments over the horizon,
   derived on every read.
5. Answer the affordability question in chat, stating its assumptions.
6. Add budgets with rollover, and progress measured against elapsed time.
7. Add the four alerts, each firing once per condition, to the admins.
8. Add the per-member "what is left" view.

Delivers: the month ahead, and not only the month behind.

---

## Phase 10 - Wishes and projects (spec 0010)

1. Let a member add a wish in one message, keep it outside the forecast, and
   promote it by giving it a date.
2. Add projects with states and targets, and the project reference on
   transactions.
3. Build project reports across categories and periods.
4. Compute feasibility and the monthly set-aside from known commitments only.
5. Ask the belongs-to-a-project question above its threshold, and never assume
   the answer.
6. Order the wishlist by affordability.

Delivers: "what did the holiday cost" and "can we have the deposit by March".

---

## Phase 11 - Moving home (spec 0011)

1. Provision the home server, and change no part of the product in this phase.
2. Carry the data, cut over, and verify balances, row counts and file hashes.
3. Run monitoring and backups from the new location, and pass the first
   verification.
4. Run the rehearsal this phase exists for: the second admin restores alone,
   from the sealed copy and the written procedure. Every step they have to
   improvise is a defect in the procedure, which you fix and then repeat the
   rehearsal.
5. Demonstrate the rebuild on an empty host.
6. Run one month of correct operation, then decommission the rented host.
7. Re-state ADR 0028's gap table with what the move closed.
8. Update `operations.md` and `deployment.md` with what the rehearsal exposed,
   which is the only reliable source of what a procedure is missing.

Delivers: the household's financial system on its own hardware, with recovery
proven by someone who did not build it.

---

## The documentation track

Documentation belongs to each phase and never becomes a phase of its own. The
table says when each document is written and which phases keep it current.

| Document | Written in | Kept current by |
|---|---|---|
| `guides/local-development.md` | Phase 0, completed phase 1 | Every phase that adds a component |
| `guides/operations.md` | Phase 1, extended phase 2 | Phases 7 and 11 |
| `guides/household-setup.md` | Phase 3 | Phases 8 and 9, which add what setup collects |
| `guides/deployment.md` | The first deployment, while doing it | Phase 11 |
| `guides/talking-to-meow.md` | Phase 3, extended each capture phase | Phases 4, 5, 8, 9 and 10: every slice that adds a view adds its questions |
| `guides/monthly-routine.md` | Phase 7 | Phase 8 |
| `guides/ui-editing.md` | Phase 6 | When Onlook's behaviour changes |
| `README.md` quickstart | Phase 1 | Whenever the first command changes |

A phase whose guide is not updated is not done, for one narrow, practical
reason: the household has two admins, and the one who did not build a thing is
the one who will need it at the worst moment.

## What is deliberately not parallelised

We sequenced five pairs on purpose, and each one below says what building them
the other way round would cost.

- Identity comes before anything that stores household data, because building
  capture first means retrofitting row-level security onto live books.
- Capture comes before reading, because a report over three test rows teaches
  nobody anything.
- Reading comes before the app, because the views are the app, and without them
  the app is a place to put numbers that do not exist yet.
- Statements come after the app, because reconciliation's output needs somewhere
  to be reviewed and its flags need a screen.
- The move home comes last, because it proves claims the earlier phases make and
  you cannot prove a claim before anyone has made it.

One thing never moves to a later phase: the documentation. It is the one thing
nobody can catch up on, because by then whoever wrote the code has forgotten what
made it worth writing down.
