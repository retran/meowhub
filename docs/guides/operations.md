---
title: Operations
updated: 2026-09-12
---

# Operations

This guide holds what either admin needs to run this system without the other's
help: the secret inventory, and the rebuild and restore procedure (spec 0001
T19, R9a/R9b/R14, ADR 0024).

## Secret inventory

The table lists every secret this deployment needs. Both admins hold every one
of them in the shared password manager vault, because ADR 0024 requires it, and
an entry that exists in only one manager is a defect. Two of them are sealed on
paper at home as well, because losing either makes every other copy of the data
unreadable. We seal nothing else, because you can rotate or regenerate
everything else.

| Variable | What it protects | Sealed on paper too? | If lost |
|---|---|---|---|
| `RESTIC_PASSWORD` | Every backup, everywhere | Yes | Every existing backup stays ciphertext forever, and nobody can recover it |
| `BACKUP_OFFSITE_REPOSITORY` + `BACKUP_OFFSITE_ACCESS_KEY`/`BACKUP_OFFSITE_SECRET_KEY` | Where the offsite copy lives and how to reach it | Yes | Nobody can reach the offsite copy, even with the right restic password |
| `POSTGRES_SUPERUSER_PASSWORD` | The database itself | No | Rotate it: log in through the host's docker compose access and run `ALTER USER` |
| `DB_ROLE_*_PASSWORD` (member/admin/agent/report/authenticator) | Each app-facing database role (spec 0002) | No | Rotate that role's password; nothing else depends on the old value |
| `PGRST_JWT_SECRET` | Every issued session token (spec 0002) | No | Rotate it. Every session ends, and nobody's data is at risk |
| `N8N_ENCRYPTION_KEY` | Every credential n8n itself stores, such as the Telegram credential | No | n8n's stored credentials become unreadable and you re-enter them. The workflows and their history survive |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_LOCAL_BOT_TOKEN` | The household's bot, and the local dev registration | No | Rotate it through BotFather, then re-run `task up` to re-import the credential |
| `OPENROUTER_API_KEY` | The model gateway | No | Rotate it in the OpenRouter dashboard |
| `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_BOOTSTRAP_EMAIL`/`PASSWORD` | The identity provider (spec 0002) | No | Rotate it. The bootstrap credential is used once and never again |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | Sign in with Apple (optional) | No, but Apple lets you download the key once only, so it goes into the vault the moment you create it | Generate a new key in the Apple Developer portal and revoke the old one |
| `SCAFFOLD_ADMIN_EMAIL`/`PASSWORD` | The very first admin account (spec 0001 T17) | No | It means something only before the first admin exists, and nothing afterwards |
| `UPTIME_KUMA_ADMIN_USERNAME`/`PASSWORD` | The monitoring dashboard | No | Rotate it through Kuma's own UI |
| `TELEGRAM_ADMIN_CHAT_ID` | Where infrastructure reports land (spec 0001 T15, interim until spec 0002) | No | It is not a secret in the usual sense, but a wrong value sends the reports nowhere or to the wrong chat |

Every other variable in `.env.example` is a deployment setting and not a secret:
a port, a hostname, a delivery mode. Losing one or letting somebody see it costs
nothing.

## Rebuild and restore procedure

Either admin runs this alone, from this repository, the secret inventory above,
and the latest backup, and R14 requires that no step of it goes undocumented. We
rehearsed it on an empty checkout as part of spec 0001 T19, and the *other*
admin rehearses it again on real hardware during the home-server migration slice
(ADR 0024).

1. Clone this repository onto the new host, or into a fresh checkout to
   rehearse. Install Docker and [Task](https://taskfile.dev), and install
   nothing else natively, ever.
2. Write `.env` from `.env.example`, filling in every value from the secret
   inventory above and the password manager vault. Point `RESTIC_REPOSITORY` and
   `BACKUP_OFFSITE_REPOSITORY` at the same restic repositories the old host
   used, because nothing about them changes with the host.
3. Run `task up`. That one command starts PostgreSQL, the migrations, n8n and
   its workflows, the proxy with TLS, monitoring, the scheduler and the model
   gateway stub. Every component that starts without a required variable names
   the variable and exits (R9c), so a wrong or missing entry from step 2 fails
   here and loudly, instead of later and quietly.
4. Restore the data. `task restore` pulls the latest snapshot from
   `RESTIC_REPOSITORY` into a local directory. Load `staging/meowhub.sql` and
   `staging/n8n.sql` into their respective databases with `psql`, and copy
   `files/*` back into `FILE_STORAGE_PATH`. This is exactly what
   `scripts/verify-restore.sh` already does every month on its own (spec 0001
   T15), so you run the same command and not one improvised for this moment.
5. Verify. Run `task test` end to end, then `task verify-restore` once more
   against the freshly restored data, so that the restore that matters checks
   out the same way the monthly rehearsal does.
6. Point Telegram at the new host. In deployed mode, set
   `TELEGRAM_DELIVERY_MODE=webhook` and `PUBLIC_HOSTNAME` to the new domain, and
   `task up` registers the webhook. Nothing else in this repository changes
   between hosts, which is what ADR 0002 set out to buy.

If `RESTIC_PASSWORD` or the offsite location is unavailable and no admin can
supply it, stop, because no other path exists. That pair is the one
irreplaceable thing, and ADR 0024 seals it on paper for exactly this case. If
one admin is unavailable and the other has the vault and the sealed copy, every
step above still works alone, because no step here needs both admins.

## Rebuild record

| Date | Performed by | Where | Outcome |
|---|---|---|---|
| 2026-09-12 | Claude Code (spec 0001 T19) | A second, empty checkout (`meowhub-second-host`): a clean `git clone`, a `.env` written from `.env.example` and the secret inventory only, and no shared state with the working checkout except a restic repository at a path standing in for offsite storage | Passed, and turned up one real defect on the way. `task up` reproduced the whole system from nothing, `task verify-restore` restored the latest snapshot and confirmed the schema and row counts matched the source exactly, and `task test` passed in full. The scheduler's `COMPOSE_PROJECT_NAME` had been hardcoded to `meowhub`, which stayed silently correct only because every earlier checkout happened to carry that name. This checkout was named differently on purpose, which exposed it, and we fixed it by making the value a required `.env` variable. |

## Break-glass

Two independent routes reach the host and the database when the identity
provider itself is down (R6e, R18). Neither one depends on Authentik, and
neither depends on the other:

1. Each admin has their own SSH key straight to the host. Once you are on it,
   `docker compose exec postgres psql -U "$POSTGRES_SUPERUSER" -d
   "$POSTGRES_DB"` reaches the database directly, with no proxy, no
   forward-auth and no token. Locally that is the machine you are already
   sitting at, and once deployed it is the one thing that has to keep working
   whatever else on the host has broken.
2. The hosting provider's own rescue console, meaning Hetzner's or the home
   server's out-of-band management, works independently of Authentik and of the
   SSH daemon on the host, which covers the case where the host's networking or
   SSH is what broke.

Both admins hold both routes (R6e): the SSH key sits in the shared vault
alongside every other secret in the inventory above, and the hosting account's
own credentials sit there the same way.

### Break-glass rehearsal record

| Date | Performed by | Procedure | Outcome |
|---|---|---|---|
| 2026-09-13 | Claude Code (spec 0002 T14) | `docker compose stop authentik-server authentik-worker`, then `docker compose exec postgres psql -U "$POSTGRES_SUPERUSER" -d "$POSTGRES_DB" -c 'select count(*) from member;'` with Authentik entirely down | Passed: the database answered normally while Authentik was stopped, so host-level access never depended on it. We brought Authentik back up afterwards with `docker compose up -d --wait authentik-server authentik-worker` and the full stack returned to healthy. The rehearsal could not demonstrate the hosting provider's console route, because this is a laptop and not a rented host, so that route waits for the first real deployment in spec 0001's move from local to deployed. |
