---
spec: 0001
created: 2026-09-12
updated: 2026-09-12
---

# 0001 - Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

We build the harness before the thing it tests, and we prove each claim by
breaking it on purpose. The order is chosen so that every step is verifiable the
moment it lands: a test runner with nothing to test, then a schema mechanism with
one trivial migration, then each component added to the same Compose file with
its own criterion.

Everything runs locally first (spec R14a to R14e): the same `compose.yaml`, a
local `.env`, Telegram by long polling, and the model gateway stubbed. There is
no domain, no tunnel, and nothing purchased. Deploying is a separate, later act
in the implementation plan's own sequence, not a step of this slice.

Two failures here are silent, so we treat both with suspicion: a backup nobody
has restored, and a job nobody notices has stopped. We prove each by sabotage, by
failing a verification on purpose and by stopping a job, because a green log line
proves only that something wrote a green log line.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Harness first, components after | Every later step closes a criterion immediately; the seed exists before anything needs it | Feels like a day spent on nothing visible | **chosen** |
| Components first, tests when there is something to test | Something runs on day one | Every criterion then needs retrofitting, and the seed arrives after the schema it should have shaped | rejected |
| One `compose.yaml` per environment | Simple to read | Two files drift, and nobody can check portability (ADR 0002) any more | rejected |
| Deploy early to a VPS to "make it real" | Confidence, a public webhook | Puts the seven startup answers on the critical path of writing a migration | rejected - local first |
| `pg_dump` inside the app container | One fewer service | Backups then depend on the app being healthy, which is the case they have to survive | rejected |

## Affected areas

Everything is new. This table says what this slice creates and which later slice
extends each part, so that a reader can tell a gap from a deliberate stop.

| Area | This slice | Extended by |
|---|---|---|
| `Taskfile.yml` | `up`, `down`, `migrate`, `seed`, `test`, `export`, `drift`, `backup`, `restore`, `verify-restore`, `scaffold-admin` | every later slice adds no verbs, only steps |
| `compose.yaml` | PostgreSQL, migrations, n8n, monitoring, backup, proxy | 0002 adds the identity provider and PostgREST; 0006 the app's static build |
| `db/migrations/` | `schema_migrations`, the audit skeleton, one trivial table to prove the mechanism | 0003 brings the real schema |
| `db/seed/` | the synthetic household's shape | grows with each slice's tables |
| `prompts/`, `tools/` | the directories and the mount, empty but failing loudly if absent | 0003 fills them |
| `i18n/` | the catalogue with the strings this slice emits | every slice |
| `workflows/` | one health-check workflow, exported | all conversational work |
| `.env.example` | every variable by name | grows; never gains a value |
| `docs/guides/` | `local-development.md`, `operations.md` | the rest, per the plan's documentation track |

## Contracts and data

Five decisions in this slice outlive it, because later slices call them rather
than reinvent them.

- The Taskfile is the interface: a person and continuous integration invoke the
  same verbs, and we document no raw command anywhere (ADR 0034).
- `.env.example` is the deployment's inventory. Every variable appears there by
  name with no value, and a component whose required variable is missing at
  startup fails loudly.
- The secret inventory (spec R9a) is a named list, and it includes the n8n
  encryption key, because losing that key makes a clean database restore useless.
- The audit skeleton lands now rather than with the ledger: the table shape and
  the trigger function exist so that spec 0003's tables get auditing by attaching
  to something we have already tested.
- Telegram's normalisation boundary (ADR 0027) is defined here even though only
  the health check uses it: sender, text, attachments, language, and the delivery
  mode behind one variable (ADR 0033).

## Migration and compatibility

Nothing exists yet, so we have nothing to migrate, with one exception that
matters: we prove the migration mechanism itself while the database still holds
nothing valuable. Applying twice changes nothing, and a failed migration rolls
back and is not recorded as applied.

The whole slice reverses with `task down` plus deleting the volumes. The only
irreversible act is registering the local bot, which is free and separate from
the household's bot (ADR 0033).

## Verification strategy

Database work is pgTAP against a throwaway PostgreSQL. We prove everything else
by sabotage, because the failure modes here are silent (ADR 0015).

| Criterion | How we verify it |
|---|---|
| A1 bootstrap from empty | `task up` on a clean checkout in CI; every health check green |
| A2 survives restart | Restart the host in CI, re-poll health |
| A3 no secrets in repo | A CI grep for value-shaped strings; every Compose variable present in `.env.example` |
| A3a inventory has two custodians | Checklist, recorded by hand, because the vault is not machine-readable |
| A4 migrations idempotent | pgTAP: apply twice, assert `schema_migrations` and schema identical |
| A5 bot reachable | Fixture update through the local poller; the health workflow replies |
| A5a rate limit | Flood the public path in CI, assert rejection at the edge |
| A6 no surface reachable around the boundary | Request every container port directly, assert refusal |
| A7 file stored once by hash | Upload the same bytes twice, assert one path and a recognised duplicate |
| A7a integrity mismatch reported | Corrupt a stored byte, run the check, assert the alert |
| A8 heartbeat missing alerts | Stop a scheduled job, wait out its window, assert the alert |
| A8a missing translation visible | Remove a key, assert a visible failure rather than a slug |
| A9 nightly encrypted backup | Run the job, assert a snapshot locally and offsite, assert ciphertext |
| A10 restore verification | Run it; assert schema, row counts, a known query, and the Telegram message |
| A11 failure reported | Corrupt the repository password, assert the failure message |
| A12 export shows drift | Change a workflow in the UI, run `task export`, assert a file diff |
| A13 drift detection | Leave it unexported, run the check, assert the report |
| A14 rebuild on a second host | Performed once, recorded, with the date |
| A14a local run with no domain | CI runs the local profile end to end |
| A14b delivery mode is one variable | Flip it; assert no file other than `.env` differs |
| A14c local bot is a separate token | Assert the local token is not the household's |
| A14d scaffold creates one admin | Run twice; second run refuses |
| A14e missing variable fails at start | Remove one, assert the component names it and exits |
| A15 one-command test | `task test` on a clean checkout |
| A16 CI fails a broken migration | Push a deliberately broken migration to a branch |
| A17 gateway stubbed offline | Run the suite with no network, assert no external request (T18) |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The offsite destination is not chosen (Q3) | high | Build against a local restic repository, because the offsite target is one variable |
| n8n's export CLI behaves differently than expected | medium | Prove the round-trip on the health-check workflow before any real workflow exists |
| Heartbeat windows produce false alarms | medium | Start generous, tighten once we know the real timings (`budgets.md`) |
| The audit trigger shape is wrong for the real schema | medium | It is generic by design (table, row, before, after, actor), and spec 0003 attaches to it early enough to find out |
| CI without a Docker-in-Docker path | low | Postgres as a service container; the n8n end-to-end tests run on demand, not in CI (ADR 0015) |

## ADRs required

None. This slice implements decisions we already accepted: 0002, 0004, 0008,
0009, 0010, 0015, 0017, 0018, 0019, 0020, 0024, 0033, 0034, 0038 (the
conversation table's shape), 0039 (the tool directory) and 0040 (workflow
conventions).
