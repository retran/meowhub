# Local development

This guide runs meowhub on a laptop, with no domain, no tunnel and nothing
purchased (spec 0001, R14a to R14e). Every phase in
[../implementation-plan.md](../implementation-plan.md) extends this page, and no
phase is done until its part is here.

## Prerequisites

You need two things, and we kept the list that short on purpose: **Docker** and
[Task](https://taskfile.dev) (`brew install go-task`). Everything else runs in
containers built from `db/docker/Dockerfile`, including PostgreSQL, dbmate and
pgTAP, so you install nothing natively.

## First run

Copy the example environment file, fill in what this phase needs, then bring the
stack up and run the tests:

```
cp .env.example .env
# fill in POSTGRES_*, DATABASE_URL at minimum for this phase
task up
task test
```

`task up` builds the Postgres and pgTAP image, starts it through Compose on the
`local` profile, and applies the migrations through the containerised `migrate`
service. `task test` runs the full suite, which today is the pgTAP tests in
`db/tests/`, executed inside the running `postgres` container against a
throwaway database that each run creates and drops.

## What exists so far

The table lists every component the repository builds today and how far each one
has got. Anything not listed here arrives in a later phase.

| Component | Status |
|---|---|
| PostgreSQL (+ pgTAP) | Built and run via Compose (`db/docker/Dockerfile`) |
| Migrations | `db/migrations/` holds the audit skeleton (ADR 0008) and the `file` table (ADR 0019), applied via the `migrate` service |
| Tests | `scripts/test-db.sh` (pgTAP) and `scripts/test-file-storage.sh` (content-addressed storage) |
| File storage | Content-addressed by SHA-256 (ADR 0019): `scripts/file-store.sh`, `scripts/file-check-integrity.sh` |
| i18n | `i18n/ru.json`, `i18n/en.json`, looked up via `scripts/i18n.sh`, where a missing key fails loudly (ADR 0017) |
| n8n | Built with a startup check that `prompts/` and `tools/` are mounted and non-empty (ADR 0025, 0039) |
| Telegram | Long polling locally, webhook when deployed, switched by `TELEGRAM_DELIVERY_MODE` in `.env` (ADR 0033). `task up` imports the credential and applies the mode automatically |
| Ingress | A Caddy reverse proxy (`proxy/Caddyfile`) is the only container with a published port, so you reach PostgreSQL and n8n only through it (spec 0001 T11) |
| PostgREST, identity provider, monitoring, backups | Arrive later in phase 1 (spec 0001) |

## The n8n editor

Open `https://localhost:${PROXY_HTTPS_PORT}/` (default `8443`) to reach the
editor through the proxy. Caddy's certificate is locally trusted but
self-signed, so your browser asks once for you to accept it. Log in with
`N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD` from `.env`. Everything
except `/webhook/*`, `/webhook-test/*` and `/healthz` reaches the editor UI,
gated by that login until spec 0002 puts a real identity provider in front of
it.

## Getting a shell

Open a psql shell in the running container:

```
docker compose exec postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB"
```

## A new migration

Create the file, edit it, apply it, and run the tests:

```
task migrate:new -- add_something
# edit db/migrations/<timestamp>_add_something.sql
task migrate
task test
```

## Workflows

The workflows live in this repository under `workflows/*.json` and they are the
source of truth. `task up` imports and activates them into n8n automatically, so
a rebuild never depends on anyone clicking through the editor. After you change
a workflow in the editor, run `task export` to write it back here, then
`task drift` to check that the running n8n and the committed files still agree.

Four workflows exist so far:

- `health-check` proves the public HTTP path reaches n8n.
- `telegram-normalize-and-dispatch` is the shared sub-workflow (ADR 0040) that
  every Telegram entry point calls: it normalises the update, deduplicates by
  `update_id`, and replies. It is always active.
- `telegram-poll` and `telegram-webhook` are the two entry points (ADR 0033).
  Both are committed inactive, and `scripts/apply-telegram-mode.sh`, driven by
  `TELEGRAM_DELIVERY_MODE`, activates exactly one. `task up` runs it for you.

We never commit the Telegram credential.
`scripts/import-telegram-credential.sh` builds it at runtime from
`TELEGRAM_LOCAL_BOT_TOKEN` locally, and a deployed host uses
`TELEGRAM_BOT_TOKEN` instead. They are two separate registrations, so local
testing can never intercept the household's real messages.

## Ingress

`docker compose up` publishes exactly one set of ports on the host: the proxy's
`PROXY_HTTP_PORT` and `PROXY_HTTPS_PORT` from `.env`. PostgreSQL and n8n publish
nothing and are reachable only from other containers on the Compose network, so
there is no direct-port shortcut around the proxy for anyone to forget about
later (spec 0001 T11).

`PUBLIC_HOSTNAME` decides how Caddy gets a certificate. A name that is not a
real public domain, such as `localhost`, an internal `.local` name or a bare IP,
gets its own locally-trusted certificate authority automatically and needs no
configuration, and a real domain gets ACME instead. Locally that means every
request goes over genuine TLS terminated by the proxy, the tests included,
instead of a plaintext stand-in.

Run `scripts/proxy-curl.sh <path> [curl args...]` whenever something in this
repository needs to talk to the stack the way Telegram or a browser would. It
pulls Caddy's local root certificate out of the running container and trusts it
for that one request instead of skipping verification. `task test:ingress` uses
it to assert that the boundary holds: PostgreSQL and n8n refuse a direct
connection, and a request through the proxy still reaches n8n.

The proxy image (`proxy/docker/Dockerfile`) is Caddy built with the
[caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) plugin, because
stock Caddy has no rate limiting and it has to be compiled in, for the same
reason `db/docker` compiles in pgTAP. Caddy limits `/webhook/*` and
`/webhook-test/*` per source address (spec 0001 T12, R5a), generously enough
that normal Telegram traffic and this repository's tests never trip it, and
tightly enough that a flood against the public webhook URL gets `429`s instead
of workflow executions. `scripts/test-rate-limit.sh` proves it by flooding the
path for real and then checking that the system answers normally once the window
passes.

## Monitoring

Uptime Kuma is admin-only tooling and not a household-facing surface, so we
never route it through the public proxy. `task up` publishes it to
`127.0.0.1:${UPTIME_KUMA_PORT}` only, which a browser on the laptop reaches
today and an SSH tunnel reaches once deployed (spec 0001 T13).

`scripts/configure-monitoring.sh` creates Kuma's admin account and its monitors
on the first run and does nothing on later runs. Kuma has no config file, only a
Socket.IO API, so `scripts/kuma-run.sh` runs a small Python script through the
`uptime-kuma-api` library against it, in a throwaway container attached to
Kuma's own network namespace. Health checks exist for PostgreSQL, the proxy and
n8n, the last of those through the proxy and over TLS, and the drift check
(`scripts/detect-drift.sh`) pushes a heartbeat when it succeeds. Kuma mints that
heartbeat's token instead of anyone choosing it by hand, and the script writes
the resulting URL into `.env` itself the first time it creates the monitor.

`scripts/test-heartbeat-alert.sh` proves the alert T13 depends on. It
creates its own scratch push monitor at Kuma's minimum interval, pushes once,
goes silent, and asserts that Kuma marks the monitor `DOWN` once the window
passes with nothing else arriving. It is a dead man's switch, and it fires on
silence where a health check fires on a bad answer.

## Databases

n8n keeps its own state in a database named `n8n` and never in meowhub's own
database, because ADR 0004 requires the household ledger to survive replacing
n8n. `db/docker/init/10-create-n8n-database.sh` creates it once, on a brand-new
PostgreSQL data directory. Anything that reaches into n8n's tables directly,
such as `scripts/apply-telegram-mode.sh` and `scripts/test-telegram-dedup.sh`,
connects to `n8n` and not to `$POSTGRES_DB`.

## Backups

`task backup` (`scripts/backup.sh`) dumps both databases and the file storage
volume, then runs restic against `RESTIC_REPOSITORY`, and again against
`BACKUP_OFFSITE_REPOSITORY` if you set it. The command is the same either way,
because restic decides from the repository string alone whether it is writing to
a local path or to S3 (spec 0001 T14, ADR 0009).
`scripts/restic-run.sh <repository> <restic args...>` is the one place that
knows how to invoke restic, in a throwaway container, bind-mounted for a local
path and credentialed for a remote one. `backup.sh` goes through it, and so will
`restore.sh` and `verify-restore.sh`. Retention is 7 daily, 4 weekly and 12
monthly (ADR 0009), applied after every backup.

`scripts/test-backup.sh` runs a real backup against two throwaway local
repositories, the second standing in for an offsite one, and asserts that a
snapshot exists in each and that neither repository holds anything readable in
plaintext on disk.

## Restore verification

`task verify-restore` (`scripts/verify-restore.sh`) restores the latest snapshot
into a scratch database, checks it against the live one for the same
`schema_migrations` versions and the same row counts, and reports the result to
Telegram whichever way it goes (spec 0001 T15, R11, ADR 0009). It pushes a
heartbeat only on a real success, so a failed run never counts as a good one.
`scripts/restore.sh` is the generic half of this, restoring the latest snapshot
to a directory, and it doubles as the real recovery command.
`scripts/telegram-report.sh` is the one place that sends a message straight to
the Bot API, outside n8n, for the reports that have to reach a human even when
nothing else can.

`TELEGRAM_ADMIN_CHAT_ID` is interim, because spec 0002 gives every admin a real
identity and routes the reports to all of them. Until then it is one chat id set
by hand, so set it to your own if you want to receive the reports. Left at the
placeholder in `.env`, the heartbeat still gets pushed and the Telegram message
itself fails, because Telegram's API rejects an invalid chat id.
`scripts/test-restore-verification.sh` avoids depending on that by pointing
`TELEGRAM_API_BASE_URL` at a throwaway local stub instead of the real API, the
same idea as `OPENROUTER_BASE_URL`'s test override (ADR 0015). That test also
proves the sabotage half of T15 directly: it corrupts a real snapshot on disk
and asserts that verification fails, reports the failure, and never pushes the
heartbeat that would count it as good.

## The scheduler

Nothing runs on the host by design, so "on a schedule" means a container.
`scheduler/docker/` builds a small image from the Docker CLI, `dcron` and
`tini`, the last because bare `crond` as PID 1 fails under some container
runtimes. It bind-mounts this repository read-only at `/workspace` and mounts
the Docker socket, so `docker compose exec` inside it reaches the same running
services your own shell does (spec 0001 T16). It has one job today: drift
detection, daily at 03:00, reported to Telegram on drift and pushing a heartbeat
on success (R13).

We set `COMPOSE_PROJECT_NAME=meowhub` explicitly on this service, because
otherwise `docker compose` inside the container would infer the project name
from the basename of `/workspace` instead of the host's real directory name, and
find nothing.

The heartbeat URLs are generated for the host's loopback address
(`127.0.0.1:UPTIME_KUMA_PORT`), which does not resolve from inside another
container. `scripts/heartbeat-curl.sh` makes a push work identically either way
by checking for `/.dockerenv` and swapping in Kuma's compose service name when
it finds it.

`task test:drift-schedule` proves the schedule is real and not only configured
on paper: it checks the crontab, then runs the exact command cron would run,
from inside the scheduler container.

## The identity boundary

Authentik, its own database, and the token bridge (ADR 0041) are built entirely
from committed blueprints in `authentik/blueprints/`: the `admin` and
`household` groups, a passkey enrollment path, a Reputation Policy gating a Deny
stage after five failed passwords, and the household app's own Proxy Provider.
We use the Reputation Policy because Enterprise's "Account Lockdown" stage is
not an option, as R17/A33 forbid any paid feature. `scripts/authentik-shell.sh`
and `scripts/authentik-curl.sh` reach Authentik's Django shell and its REST API,
using the same "borrow the target container's network namespace" trick as
`scripts/kuma-run.sh`.

`proxy/Caddyfile` wires the full request path for the data API under `/rest/*`:
Authentik forward-auth, the token bridge, then PostgREST (spec 0002 T9; the
household app itself belongs to spec 0006). `scripts/authentik-e2e-signin.py`
drives a real sign-in through that whole path, run from the host against the
proxy's published port the way a browser would: identification, password, the
OAuth authorize and callback exchange Authentik's Proxy Provider does for its
own application, and finally a request that reaches PostgREST and brings the
member's own row back.

Authentik has a known limitation here that is not a meowhub bug
([goauthentik/authentik#12503](https://github.com/goauthentik/authentik/issues/12503)):
on a non-standard HTTPS port, such as `PROXY_HTTPS_PORT` at `8443` locally, the
OAuth authorize redirect Authentik generates for itself loses the scheme and the
port. It comes out as a bare `http://localhost/...` instead of
`https://localhost:8443/...`, and neither a script nor a real browser can follow
it as it stands. `authentik-e2e-signin.py` corrects it on the client side to
prove the rest of the chain is sound, and if you hit this in a browser during
local sign-in, edit the address bar to add `https://` and `:8443` before you
continue. A real deployment on the standard port 443 never hits it.

## Admin-only surfaces

n8n's editor and Uptime Kuma's dashboard are admin-only (R17a). Both sit behind
the same Authentik forward-auth check every other route uses, plus a second
check in `proxy/Caddyfile`: a `forward_auth` call to the token bridge's
`/require-group/admin`, which answers 200 or 403 depending on whether the
signed-in subject holds the `admin` group. A non-2xx answer aborts the request
with that status, chaining the same way `/rest/*` already chains to the token
bridge proper.

That second check does not use Authentik's own `X-Authentik-Groups` forward-auth
response header, even though Caddy's `copy_headers` makes it available for
exactly this. We found a real bug in this slice: whether the header appeared
turned out to depend on which OAuth scopes happened to be negotiated for a given
request, and the same Proxy Provider and the same signed-in user got it on one
path and not on another. The token bridge instead queries Authentik's own API
directly through `GET /api/v3/core/users/`, authenticated as a dedicated service
account (`authentik/blueprints/04-token-bridge-account.yaml`) whose own group is
a superuser group. We chose that deliberately for a trusted internal service
that must always be able to make this read, and it is the same trust level n8n
and Authentik's own containers already have when they connect to PostgreSQL as
its superuser. `scripts/configure-token-bridge.sh` writes the service account's
generated API token into `.env` during `task up`, the same generated-credential
pattern `scripts/configure-monitoring.sh` uses for Kuma's push URLs.

Uptime Kuma's own login is disabled entirely, through
`scripts/configure-monitoring.sh` with `disableAuth: true`, because the boundary
above is its only gate. Its push-heartbeat endpoint was never login-gated to
begin with, since it is token-scoped by design, so disabling the login removes
no protection a heartbeat relied on. Authentik's own admin interface is the
third surface in R17a's table, and it needs no extra gating here because it
authenticates itself. That is deliberately self-referential: if Authentik is
misconfigured, the boundary and its own admin are lost together, which is
exactly why the break-glass path in R18/T14 exists and why this configuration
lives in blueprints instead of clicks.

## Accounts: creation, forced password change, deactivation

Nobody signs themselves up (R1). `scripts/create-member.sh <role> <email>
[admin_member_id]` is the only way a member's account comes to exist, in
Authentik and in `member` and `member_identity` together. Every account after
the first needs a real admin's own member id, attributed in the audit log the
same as any other admin action. The very first account has no admin to name, so
that one case, where `member` holds no rows yet, writes with a fixed bootstrap
actor instead and refuses outright once any account exists (R14a/b).
`task scaffold-admin` (`scripts/scaffold-admin.sh`) calls that same script in
its bootstrap form, supplying `SCAFFOLD_ADMIN_EMAIL` and
`SCAFFOLD_ADMIN_PASSWORD` from the environment.

The password an admin sets is temporary (R1d), and the account reaches nothing
until somebody changes it. Authentik has no built-in "must change" flag, so
`authentik/blueprints/05-forced-password-change.yaml` reuses the two stages its
own self-service `default-password-change` flow already has, a password prompt
and then a write, by binding them into `default-authentication-flow` as well. A
policy gates them by comparing the account's `password_change_date`, a real
column that Authentik's own `set_password()` updates on every change, against
`password_set_by_admin_at`, an attribute `create-member.sh` records right after
it sets the temporary password. Equal values mean nothing has changed the
password since the admin set it, and changing it moves `password_change_date` so
the gate opens on its own, with no separate step to clear anything.

A departure is a designed event and never a deletion (ADR 0026).
`scripts/deactivate-member.sh <admin_member_id> <member_id>` sets
`member.active = false`, which keeps the row so that every past transaction
keeps its submitter, disables the Authentik account, ends every session it
currently holds, because disabling `is_active` alone does not invalidate a
cookie already issued, and revokes its passkeys. The token bridge also checks
`member.active` directly and refuses to mint for an inactive member on the very
next request. That check is a narrow defence for the gap between deactivation
and Authentik's own account state catching up, and not the main defence.

## Setting up and using the household's own bot

[household-setup.md](household-setup.md) says what the setup conversation asks
and why. [talking-to-meow.md](talking-to-meow.md) says what a member can say, in
either language, and what happens next (spec 0003).

## CI

`.github/workflows/ci.yml` runs `task up` and `task test` with the same
`Taskfile.yml` on GitHub-hosted Docker, so there is no separate CI-only setup to
keep in sync with local development.

## Deploying and recovering

[operations.md](operations.md) holds the secret inventory and the rebuild and
restore procedure: what either admin needs to run this system without the
other's help, on a rented host or on the home server (spec 0001 T19).
