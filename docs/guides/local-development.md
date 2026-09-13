# Local development

Runs meowhub on a laptop: no domain, no tunnel, nothing purchased (spec 0001,
R14a–R14e). This page is extended by every phase in
[../implementation-plan.md](../implementation-plan.md); a phase is not done
until its part is here.

## Prerequisites

Two things, deliberately: **Docker** and **[Task](https://taskfile.dev)**
(`brew install go-task`). Everything else — PostgreSQL, dbmate, pgTAP — runs in
containers, built from `db/docker/Dockerfile`. Nothing is installed natively.

## First run

```
cp .env.example .env
# fill in POSTGRES_*, DATABASE_URL at minimum for this phase
task up
task test
```

`task up` builds the Postgres+pgTAP image, starts it via Compose on the `local`
profile, and applies migrations through the containerised `migrate` service.
`task test` runs the full suite — today, the pgTAP tests in `db/tests/`,
executed inside the running `postgres` container against a throwaway database
created and dropped on every run.

## What exists so far

| Component | Status |
|---|---|
| PostgreSQL (+ pgTAP) | Built and run via Compose (`db/docker/Dockerfile`) |
| Migrations | `db/migrations/` — the audit skeleton (ADR 0008) and the `file` table (ADR 0019), applied via the `migrate` service |
| Tests | `scripts/test-db.sh` (pgTAP) and `scripts/test-file-storage.sh` (content-addressed storage) |
| File storage | Content-addressed by SHA-256 (ADR 0019): `scripts/file-store.sh`, `scripts/file-check-integrity.sh` |
| i18n | `i18n/ru.json`, `i18n/en.json`, looked up via `scripts/i18n.sh` — a missing key fails loudly (ADR 0017) |
| n8n | Built with a startup check that `prompts/` and `tools/` are mounted and non-empty (ADR 0025, 0039) |
| Telegram | Long polling locally, webhook when deployed, switched by `TELEGRAM_DELIVERY_MODE` in `.env` (ADR 0033). `task up` imports the credential and applies the mode automatically |
| Ingress | A Caddy reverse proxy (`proxy/Caddyfile`) is the only container with a published port; PostgreSQL and n8n are reachable only through it (spec 0001 T11) |
| PostgREST, identity provider, monitoring, backups | Arrive later in phase 1 (spec 0001) |

## The n8n editor

`https://localhost:${PROXY_HTTPS_PORT}/` (default `8443`), through the
proxy — Caddy's certificate is locally trusted but self-signed, so a
browser asks once to accept it. Logs in with `N8N_BASIC_AUTH_USER` /
`N8N_BASIC_AUTH_PASSWORD` from `.env`. Everything except `/webhook/*`,
`/webhook-test/*` and `/healthz` reaches the editor UI, gated by that
login until spec 0002 puts a real identity provider in front of it.

## Getting a shell

```
docker compose exec postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB"
```

## A new migration

```
task migrate:new -- add_something
# edit db/migrations/<timestamp>_add_something.sql
task migrate
task test
```

## Workflows

Workflows live in this repository (`workflows/*.json`) and are the source of
truth: `task up` imports and activates them into n8n automatically, so a
rebuild never depends on clicking through the editor. After changing a
workflow in the editor, run `task export` to write it back here, and
`task drift` to check whether the running n8n and the committed files still
agree.

Four workflows exist so far:

- `health-check` — proves the public HTTP path reaches n8n.
- `telegram-normalize-and-dispatch` — the shared sub-workflow (ADR 0040) every
  Telegram entry point calls: normalises the update, deduplicates by
  `update_id`, replies. Always active.
- `telegram-poll` and `telegram-webhook` — the two entry points (ADR 0033).
  Both are committed inactive; `scripts/apply-telegram-mode.sh`, driven by
  `TELEGRAM_DELIVERY_MODE`, activates exactly one and is run automatically by
  `task up`.

The Telegram credential is never committed: `scripts/import-telegram-credential.sh`
builds it at runtime from `TELEGRAM_LOCAL_BOT_TOKEN` (local) — a deployed host
would use `TELEGRAM_BOT_TOKEN` instead, a separate registration so local
testing can never intercept the household's real messages.

## Ingress

`docker compose up` publishes exactly one port set on the host: the proxy's
`PROXY_HTTP_PORT`/`PROXY_HTTPS_PORT` (`.env`). PostgreSQL and n8n publish
nothing — they are reachable only from other containers on the Compose
network, so there is no direct-port shortcut around the proxy to forget about
later (spec 0001 T11).

`PUBLIC_HOSTNAME` decides how Caddy gets a certificate: a name that isn't a
real public domain (`localhost`, an internal `.local` name, a bare IP) gets
its own locally-trusted certificate authority automatically, no configuration
needed; a real domain gets ACME instead. Locally that means every request —
including the tests — goes over genuine TLS, terminated by the proxy, not a
plaintext stand-in for it.

`scripts/proxy-curl.sh <path> [curl args...]` is how anything in this
repository talks to the stack the way Telegram or a browser would: it pulls
Caddy's local root certificate out of the running container and trusts it for
that one request, rather than skipping verification. `task test:ingress` uses
it to assert the boundary holds — PostgreSQL and n8n refuse a direct
connection, and a request through the proxy still reaches n8n.

The proxy image (`proxy/docker/Dockerfile`) is Caddy built with the
[caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) plugin — stock
Caddy has no rate limiting, so it has to be compiled in, same reasoning as
`db/docker`'s pgTAP. `/webhook/*` and `/webhook-test/*` are limited per
source address (spec 0001 T12, R5a): generous enough that normal Telegram
traffic and this repository's tests never trip it, tight enough that a flood
against the public webhook URL gets `429`s instead of workflow executions.
`scripts/test-rate-limit.sh` proves it by actually flooding the path and
checking the system is still answering normally once the window passes.

## Monitoring

Uptime Kuma is admin-only tooling, not a household-facing surface, so it is
never routed through the public proxy — `task up` publishes it to
`127.0.0.1:${UPTIME_KUMA_PORT}` only, reachable in a browser on the laptop
today and by an SSH tunnel once deployed (spec 0001 T13).

`scripts/configure-monitoring.sh` creates its admin account and its monitors
on first run and is idempotent after that — Kuma has no config file, only a
Socket.IO API, so `scripts/kuma-run.sh` runs a small Python script (the
`uptime-kuma-api` library) against it in a throwaway container attached to
Kuma's own network namespace. Health checks exist for PostgreSQL, the proxy
and n8n (through the proxy, over TLS); the drift check
(`scripts/detect-drift.sh`) pushes a heartbeat on success. That heartbeat's
token is minted by Kuma, not chosen by hand: the script writes the resulting
URL into `.env` itself the first time the monitor is created.

`scripts/test-heartbeat-alert.sh` proves the actual mechanism T13 depends
on: it creates its own scratch push monitor at Kuma's minimum interval,
pushes once, goes silent, and asserts Kuma marks it `DOWN` once the window
passes with nothing else — a dead man's switch, not a health check.

## Databases

n8n keeps its own state in a database named `n8n`, never in `meowhub`'s own
database (ADR 0004: the household ledger must survive replacing n8n) —
created once, on a brand-new PostgreSQL data directory, by
`db/docker/init/10-create-n8n-database.sh`. Anything that reaches into n8n's
tables directly (`scripts/apply-telegram-mode.sh`,
`scripts/test-telegram-dedup.sh`) connects to `n8n`, not `$POSTGRES_DB`.

## Backups

`task backup` (`scripts/backup.sh`) dumps both databases and the file
storage volume, then runs restic against `RESTIC_REPOSITORY`, and again
against `BACKUP_OFFSITE_REPOSITORY` if it is set — the exact same command
either way, since restic itself decides local-path-versus-S3 purely from
the repository string (spec 0001 T14, ADR 0009).
`scripts/restic-run.sh <repository> <restic args...>` is the one place that
knows how to invoke restic (a throwaway container, bind-mounted for a local
path, credentialed for a remote one) — `backup.sh`, and later `restore.sh`
and `verify-restore.sh`, all go through it. Retention is 7 daily, 4 weekly,
12 monthly (ADR 0009), applied after every backup.

`scripts/test-backup.sh` runs a real backup against two throwaway local
repositories (the second standing in for an offsite one) and asserts a
snapshot exists in each and that neither repository holds anything
readable in plaintext on disk.

## Restore verification

`task verify-restore` (`scripts/verify-restore.sh`) restores the latest
snapshot into a scratch database, checks it against the live one — the
same `schema_migrations` versions applied, the same row counts — and
reports the result to Telegram either way (spec 0001 T15, R11, ADR 0009).
A heartbeat is only pushed on real success, so a failed run is never
counted as good. `scripts/restore.sh` is the generic half of this (restore
the latest snapshot to a directory) and doubles as the real recovery
command; `scripts/telegram-report.sh` is the one place that sends a
message straight to the Bot API, outside n8n, for reports that must reach
a human even when nothing else can.

`TELEGRAM_ADMIN_CHAT_ID` is deliberately interim: spec 0002 gives every
admin a real identity and routes reports to all of them. Until then it is
one chat id set by hand — set it to your own to actually receive reports;
left at the placeholder in `.env`, the heartbeat still gets pushed but the
Telegram message itself will fail (Telegram's API rejects an invalid chat
id), which `scripts/test-restore-verification.sh` avoids depending on by
pointing `TELEGRAM_API_BASE_URL` at a throwaway local stub instead of the
real API — the same idea as `OPENROUTER_BASE_URL`'s test override (ADR
0015). That test also proves the sabotage half of T15 directly: it corrupts
a real snapshot on disk and asserts verification fails, reports failure,
and never pushes the heartbeat that would count it as good.

## The scheduler

Nothing runs on the host by design, so "on a schedule" means a container:
`scheduler/docker/` builds a small image (Docker CLI + `dcron` + `tini`,
since bare `crond` as PID 1 fails under some container runtimes) with this
repository bind-mounted read-only at `/workspace` and the Docker socket
mounted, so `docker compose exec` inside it reaches the same running
services a developer's own shell does (spec 0001 T16). Its one job today:
drift detection, daily at 03:00, reported to Telegram on drift and a
heartbeat pushed on success (R13).

`COMPOSE_PROJECT_NAME=meowhub` is set explicitly on this service —
otherwise `docker compose` inside the container would infer the project
name from `/workspace`'s basename instead of the host's real directory
name, and find nothing.

Heartbeat URLs are generated for the host's loopback address
(`127.0.0.1:UPTIME_KUMA_PORT`), which does not resolve from inside another
container; `scripts/heartbeat-curl.sh` is what makes a push work
identically either way, by checking for `/.dockerenv` and swapping in
Kuma's compose service name when it's set.

`task test:drift-schedule` proves the schedule is real, not just
configured on paper: it checks the crontab, then actually runs the exact
command cron would, from inside the scheduler container.

## The first admin

`task scaffold-admin` (`scripts/scaffold-admin.sh`) creates the first admin
from `SCAFFOLD_ADMIN_EMAIL`/`SCAFFOLD_ADMIN_PASSWORD`, hashed with
pgcrypto's bcrypt and marked initial, and refuses outright if any account
already exists (spec 0001 T17, R14e). `admin_account` (migration
`20260912000004_admin_scaffold.sql`) is a deliberately minimal scaffold —
just enough to prove the mechanism before any identity design exists; spec
0002 replaces it with the real accounts/members/roles schema.

## CI

`.github/workflows/ci.yml` runs `task up` and `task test` with the same
`Taskfile.yml`, on GitHub-hosted Docker — no separate CI-only setup to keep in
sync with local development.

## Deploying and recovering

[operations.md](operations.md) has the secret inventory and the rebuild
and restore procedure — what either admin needs to run this system without
the other's help, on a rented host or the home server (spec 0001 T19).
