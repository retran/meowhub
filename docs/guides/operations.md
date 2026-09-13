---
title: Operations
updated: 2026-09-12
---

# Operations

What either admin needs to run this system without the other's help: the
secret inventory, and the rebuild-and-restore procedure (spec 0001 T19,
R9a/R9b/R14, ADR 0024).

## Secret inventory

Every secret this deployment needs. Both admins hold every one of these in
the shared password manager vault, per ADR 0024 — an entry that exists in
only one manager is a defect. Two are sealed on paper at home as well,
because losing them makes every other copy of the data unreadable; nothing
else is sealed, because everything else can be rotated or regenerated.

| Variable | What it protects | Sealed on paper too? | If lost |
|---|---|---|---|
| `RESTIC_PASSWORD` | Every backup, everywhere | **Yes** | Every existing backup is ciphertext forever — unrecoverable |
| `BACKUP_OFFSITE_REPOSITORY` + `BACKUP_OFFSITE_ACCESS_KEY`/`BACKUP_OFFSITE_SECRET_KEY` | Where the offsite copy lives and how to reach it | **Yes** | The offsite copy is unreachable even with the right restic password |
| `POSTGRES_SUPERUSER_PASSWORD` | The database itself | No | Rotate: log in via the host's docker compose access, `ALTER USER` |
| `DB_ROLE_*_PASSWORD` (member/admin/agent/report/authenticator) | Each app-facing database role (spec 0002) | No | Rotate the role's password; nothing else depends on the old value |
| `PGRST_JWT_SECRET` | Every issued session token (spec 0002) | No | Rotate; every session is invalidated, nobody's data is at risk |
| `N8N_ENCRYPTION_KEY` | Every credential n8n itself stores (the Telegram credential, etc.) | No | n8n's stored credentials become unreadable and must be re-entered — workflows and their history survive |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_LOCAL_BOT_TOKEN` | The household's bot / the local dev registration | No | Rotate via BotFather; re-run `task up` to re-import the credential |
| `OPENROUTER_API_KEY` | The model gateway | No | Rotate in the OpenRouter dashboard |
| `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_BOOTSTRAP_EMAIL`/`PASSWORD` | The identity provider (spec 0002) | No | Rotate; the bootstrap credential is only used once |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | Sign in with Apple (optional) | No — but downloadable only once from Apple, so it goes in the vault the moment it's created | Generate a new key in the Apple Developer portal, revoke the old one |
| `SCAFFOLD_ADMIN_EMAIL`/`PASSWORD` | The very first admin account (spec 0001 T17) | No | Only meaningful before the first admin exists; harmless afterward |
| `UPTIME_KUMA_ADMIN_USERNAME`/`PASSWORD` | The monitoring dashboard | No | Rotate via Kuma's own UI |
| `TELEGRAM_ADMIN_CHAT_ID` | Where infrastructure reports land (spec 0001 T15, interim until spec 0002) | No | Not a secret in the usual sense, but wrong value means reports go nowhere or somewhere wrong |

Every other variable in `.env.example` is a deployment setting, not a
secret — a port, a hostname, a delivery mode. It costs nothing to lose or
to see.

## Rebuild and restore procedure

Either admin, alone, from this repository, the secret inventory above, and
the latest backup — no undocumented step (R14). Rehearsed on an empty
checkout as part of spec 0001 T19; rehearsed again by the *other* admin, on
real hardware, during the home-server migration slice (ADR 0024).

1. **Clone this repository** onto the new host (or a fresh checkout, to
   rehearse). Install Docker and [Task](https://taskfile.dev) — nothing
   else is installed natively, ever.
2. **Write `.env`** from `.env.example`, filling in every value from the
   secret inventory above and the password manager vault. `RESTIC_REPOSITORY`
   and `BACKUP_OFFSITE_REPOSITORY` point at the same restic repositories the
   old host used — nothing about them changes with the host.
3. **`task up`.** One command: PostgreSQL, migrations, n8n and its
   workflows, the proxy with TLS, monitoring, the scheduler, the model
   gateway stub. Every component that starts without a required variable
   names it and exits (R9c) — a wrong or missing entry in step 2 fails
   loudly here, not later.
4. **Restore the data.** `task restore` pulls the latest snapshot from
   `RESTIC_REPOSITORY` to a local directory; load `staging/meowhub.sql` and
   `staging/n8n.sql` into their respective databases with `psql`, and copy
   `files/*` back into `FILE_STORAGE_PATH`. This is exactly what
   `scripts/verify-restore.sh` already does automatically every month
   (spec 0001 T15) — the same command, not a special one improvised for
   this moment.
5. **Verify.** `task test` end to end, then `task verify-restore` once more
   against the freshly restored data, to confirm the restore that matters —
   the real one — checks out the same way the monthly rehearsal does.
6. **Point Telegram at the new host.** Deployed mode: set
   `TELEGRAM_DELIVERY_MODE=webhook` and `PUBLIC_HOSTNAME` to the new
   domain; `task up` registers the webhook. Nothing else in this repository
   changes between hosts — that is the whole point of ADR 0002.

**If the RESTIC_PASSWORD or the offsite location is unavailable and no
admin can supply it**: stop. There is no other path — that is the one
irreplaceable pair, sealed on paper for exactly this reason (ADR 0024). If
one admin is unavailable but the other has the vault and the sealed copy,
every step above still works alone; nothing here requires both.

## Rebuild record

| Date | Performed by | Where | Outcome |
|---|---|---|---|
| 2026-09-12 | Claude Code (spec 0001 T19) | A second, empty checkout (`meowhub-second-host`) — a clean `git clone`, a `.env` written from `.env.example` and the secret inventory only, no shared state with the working checkout except a restic repository at a path standing in for offsite storage | Passed, with one real finding fixed along the way: `task up` reproduced the whole system from nothing; `task verify-restore` restored the latest snapshot and confirmed schema and row counts matched the source exactly; `task test` passed in full. The scheduler's `COMPOSE_PROJECT_NAME` had been hardcoded to `meowhub` — silently correct only because every prior checkout happened to be named that. This second checkout, deliberately named differently, exposed it; fixed by making it a required `.env` variable instead. |
