---
spec: 0002
created: 2026-09-12
updated: 2026-09-12
---

# 0002 - Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

We work bottom-up, in the same order as spec 0001: build the piece that proves
the mechanism before the piece that depends on it, and close every acceptance
criterion by impersonation or a real request rather than by reading the
configuration back. The seven steps run in this order:

1. The real identity tables (`member`, `member_identity`, `member_channel`)
   replace spec 0001 T17's `admin_account` scaffold outright, because we built
   that scaffold so that it would not survive this migration.
2. Authentik runs as a container, configured entirely by blueprints (ADR 0010):
   the `admin` and `household` groups, the Apple federated source (behind a
   feature flag while Q1 is open), passkey enrolment, and a Proxy Provider per
   surface.
3. The token bridge (ADR 0041) is the one new service this slice adds, and we
   test it in isolation before anything is wired through it.
4. The proxy path goes from Authentik forward-auth to the token bridge to
   PostgREST. We extend it to the surfaces named in R17a one at a time and prove
   each one on its own. n8n's editor already sits behind the proxy (spec 0001
   T18), so here we add the forward-auth hop in front of what is already there.
5. Row-level security comes next: the database roles from R15b, and policies on
   every table that exists so far, proven by impersonation before anything else
   reads through them.
6. Telegram linking follows, as the one-time-code flow (ADR 0030), with
   attribution keyed on member id.
7. The scaffold, the break-glass path, and everything else that only matters
   once come last: the first admin, the SSH keys, and the documented recovery
   path.

The household app itself, its screens and its PostgREST client, is spec 0006's
job. This slice proves the path with curl and psql, not with a UI.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Authentik's Proxy Provider forward-auth, plus a token bridge (ADR 0041) | One boundary for every surface (R17b), no paid tier anywhere, the token shape stays exactly PostgREST's own contract | One more small service in the request path | **chosen** |
| Configure Authentik as a full OIDC provider, verify its JWT directly at PostgREST | Fewer moving parts on paper | Authentik's claims aren't shaped for a PostgreSQL role or our member id; the translation has to happen somewhere, and doing it in Authentik's own UI is configuration-as-clicks, which ADR 0010 excludes | rejected |
| Build identity and RLS before Authentik exists, stub the token | Unblocks database work immediately | The stub becomes the thing every policy is tested against, and the real token shape is only checked at the end, which is the failure mode ADR 0015 exists to prevent | rejected |
| Roll Telegram linking into the same migration as `member` and `member_identity` | One migration, one commit | `member_channel` and the one-time-code flow need the bot to be able to prompt someone, which needs identity first, so sequencing this early inverts the real dependency | rejected - linking comes after roles exist |

## Affected areas

This table says what this slice adds to each area and which later slice extends
it, so that a reader can tell a gap from a deliberate stop.

| Area | This slice | Extended by |
|---|---|---|
| `compose.yaml` | Authentik (server + worker + its own Postgres database, per ADR 0004's separate-database rule), PostgREST, the token bridge | spec 0006 adds the app's own static build |
| `db/migrations/` | `member`, `member_identity`, `member_channel`; drops `admin_account`; the six roles from R15b and their grants; RLS policies for every table spec 0001 created (`file`, `audit_log`) | spec 0003 brings the ledger's own tables and their policies |
| `authentik/blueprints/` | Groups, the Proxy Provider per surface, the Apple source (flagged), passkey policy | grows as later specs add surfaces |
| `proxy/Caddyfile` | `forward_auth` to Authentik's outpost, then to the token bridge, for every surface in R17a's table | none, because the pattern is fixed here |
| `token-bridge/` | New service (ADR 0041): resolves an Authentik identity to a member and a role, mints a short-lived PostgREST JWT | none planned |
| `scripts/scaffold-admin.sh` | Rewritten: creates the first Authentik user and the matching `member` and `member_identity` rows, not a password in our own schema | superseded again only if Authentik's own bootstrap changes |
| `workflows/` | The Telegram linking workflow: an unlinked sender gets a one-time code, and an admin confirms it | none planned |
| `i18n/` | Strings for the linking flow and the "you are not linked" reply | every slice |

## Contracts and data

Later slices call these tables, roles and token claims, so they are fixed here
rather than in the code that happens to write them first.

- Tables, whose names `docs/architecture/data-model.md` already fixes:
  - `member(id, role, language, theme, default_payment_account_id, active, created_at)`,
    where `role` is `admin` or `member` (R7).
  - `member_identity(member_id, provider_subject, created_at)`, unique on
    `provider_subject`, matched on that subject and never on email (R4).
  - `member_channel(member_id, kind, external_id, linked_by, linked_at)`, unique
    on `(kind, external_id)`, with `kind = 'telegram'` today (R6a).
- The database roles: R15b's table is the contract, and the migrations create
  exactly those six roles, `anon`, `hh_member`, `hh_admin`, `hh_agent`,
  `hh_report`, and `authenticator`.
- The PostgREST JWT, minted by the token bridge (ADR 0041), carries `role` (one
  of the six above) and `member_id` (our own identifier, R15a). It is HS256,
  signed with `PGRST_JWT_SECRET`, and short-lived.
- The token bridge's own contract: given a request that already carries
  Authentik's forward-auth headers, it responds with a token or refuses. It
  reads no request body, keeps no session of its own, and caches nothing across
  requests.
- `docs/architecture/data-model.md` gains no new view this slice, because RLS on
  the existing tables enforces R9 and R10 and no new figure is computed.

## Migration and compatibility

- `admin_account` (spec 0001 T17) is dropped rather than carried forward,
  because we built it as a scaffold to be superseded here. We don't migrate its
  one row if it exists; the new scaffold command creates the real first admin
  fresh, in Authentik and in `member` and `member_identity` together.
- Every table spec 0001 created gets a policy before this slice is done. `file`
  and `audit_log` are reachable today with no row-level security at all, which
  is only safe while nothing has authenticated yet. Default deny (R14, and the
  spec's own edge case table) means a table with no policy is unreachable rather
  than open, so we close this gap here and don't defer it to spec 0003.
- The slice is reversible: every migration has a `down`, Authentik's blueprints
  are declarative and can be re-applied, and the token bridge is stateless.

## Verification strategy

Database and role tests are pgTAP, run by impersonation: `set local role` to
each of the six roles and assert what succeeds and what fails, never asserting
from the policy text (ADR 0015). Anything through the proxy is a real HTTP
request against the running stack, the same pattern spec 0001's tests already
use.

| Acceptance criterion | How we verify it |
|---|---|
| A1 | Fresh member via the scaffold's sibling command (an admin-only creation path, never self-service); sign in with email+password against Authentik directly; confirm the resulting session reaches `hh_member`-level surfaces |
| A1a | Create a member with a known email; sign in with a stub Apple identity reporting that same email; assert the resulting `member_identity` row attaches to the existing member with no separate confirmation step. Authentik's own source config (`user_matching_mode: email_link`) does this natively, so nothing in our own schema keys on email at all |
| A1b | Sign in with a freshly admin-created account's temporary password; assert the session reaches nothing until a password change; change it; assert the old password no longer authenticates |
| A2 | Enrol a passkey and an Apple link on the same session; assert one `member_identity` row per method, same `member_id` |
| A3 | Admin with only a password attempts an admin-only Proxy Provider; assert refusal until a second method is enrolled (Authentik policy, checked by requesting the surface) |
| A4 | Scripted repeated failed password attempts against Authentik; assert lockout and an audit entry |
| A5 | No SMTP configured anywhere in this stack (grep the compose file and env inventory); admin-performed reset via Authentik's own console, audited |
| A6 | Sign in with Apple against one Proxy Provider, then request a second without a new sign-in; assert success (SSO) |
| A7 | Two Apple sign-ins with Hide My Email; assert one `member_identity` row, matched on subject |
| A8 | Passkey-only sign-in path exercised against Authentik's WebAuthn endpoint |
| A9 | Apple source disabled in the blueprint; passkey sign-in still reaches admin surfaces |
| A10 | `hh_member` role requests a Proxy Provider gated to `admin`; assert refusal |
| A11 | pgTAP, impersonating `hh_member`: `delete` on a recorded transaction fails |
| A12 | pgTAP, impersonating `hh_member`: category/project update succeeds |
| A13 | pgTAP, impersonating `hh_member`: insert on a posting-shaped table fails under every role except through the confirmation function |
| A14 | Every exposed view, requested via PostgREST with no `Authorization` header, returns empty or refused, one view at a time rather than sampled |
| A15 | A token with its `role` claim altered (re-signed with a different secret) is rejected by PostgREST |
| A16 | An expired token (minted with a past `exp`) is rejected |
| A17 | `member.active = false`; sign-in attempts fail and the token bridge refuses to mint for that member even mid-session |
| A18 | Unlinked Telegram id messages the bot; assert nothing written, the audit log records the attempt, the reply is the generic denial string |
| A19 | Admin links a Telegram id; a capture attributes to the member; re-link to a second account; assert the original transaction's `member_id` is unchanged |
| A20 | Member with no `member_channel` row signs into the app path directly; assert it succeeds |
| A21 | The rewritten scaffold run once from empty; run twice; assert refusal the second time (same pattern as spec 0001 T17's test) |
| A22 | Authentik subject with no `member_identity` row; token bridge refuses to mint; assert no request reaches PostgREST at all |
| A23 | pgTAP: `select * from information_schema.role_table_grants` per role, diffed against R15b's table verbatim |
| A24 | pgTAP, impersonating `hh_agent`: insert with no acting member set fails |
| A25 | A scripted request against the app's built path (or, this slice, the token bridge's own test harness) inspects response headers and cookies for any bearer token, and asserts there is none |
| A26 | PostgREST's own port, requested directly rather than through the proxy: refused (same pattern as spec 0001 T11's ingress boundary test) |
| A27 | Authentik stopped (`docker compose stop authentik`); SSH access and a direct `psql` session both still work; recorded once, dated, the same way spec 0001 T19 recorded its rebuild |
| A28 | Two passkeys enrolled; one revoked via Authentik's admin API; assert the revoked one fails and the other still signs in |
| A29 | Admin's non-device-bound factor (a recovery code) used in place of a "lost phone"; assert sign-in still succeeds |
| A30 | Each of the three members, impersonated in pgTAP, reads the full ledger, asserted row-for-row equal across all three |
| A31 | `hh_member` confirms their own unconfirmed capture: succeeds; attempts another member's: fails |
| A32 | Grep the app's build output (once spec 0006 produces one) for anything secret-shaped, tracked here as a standing check and closed when the app exists |
| A33 | Every Proxy Provider reached with the free Authentik feature set only, with no license key anywhere in the blueprints |
| A34 | One sign-in, then each administrative Proxy Provider in turn, asserting no second Authentik prompt except n8n's own documented password |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Apple Developer membership not yet held (Q1) | high | Every criterion above is provable with email+password and passkeys alone; the Apple source is a blueprint behind a flag, added without touching anything else when Q1 resolves |
| Authentik's blueprint format changes between versions | low | Pin the image tag, as every other container in this repository already does |
| The token bridge becomes a second place authorisation logic can drift from RLS | medium | The bridge only ever decides which role and which member id, and holds no table-level permission logic itself; A23 checks the database's actual grants independently of anything the bridge asserts |
| Passkey re-enrolment on a domain change is forgotten during the home-server migration | medium | Named explicitly in ADR 0006 and in the migration slice's own task list (spec 0011), rather than left implicit here |

## ADRs required

- ADR 0041, "Authentik authenticates the session; a token bridge mints the
  PostgREST JWT". We drafted it alongside this plan, because the request path
  through the boundary is exactly what several acceptance criteria (A14 to A17,
  A22, and A25) test directly.
