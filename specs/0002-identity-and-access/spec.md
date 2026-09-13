---
id: 0002
title: Identity and access
status: done
created: 2026-09-12
updated: 2026-09-13
owner: admins
supersedes: []
---

# 0002 — Identity and access

## Problem

Every later slice sits behind this one. The bot must know who is speaking before
a transaction can be attributed; the app must know who is looking before it shows
a household's complete financial picture; and the boundary that decides both is
the single place where a mistake does not crash anything — it silently shows one
person's money data to someone who should not see it, or lets a stray tap rewrite
years of books.

It is also the slice with the most parts that can be wrong quietly: a permission
enforced in one caller but not another, a policy that looks right and admits
everyone, a token accepted without its claims being checked.

## Why

After this slice, a known person reaches exactly what their role allows, through
one boundary, enforced in the database rather than in any caller — and that is
demonstrated by impersonation rather than by reading the configuration.

The measure: every member signs in on their own phone with a biometric and no
password, and an attempt to exceed a role fails at the database.

## Users and scenarios

- **An admin** wants to reach the automation editor from a phone with Face ID,
  so that administration does not depend on a shared password.
- **A member** wants to open the household app without creating an account or
  remembering anything.
- **A member** wants to sign in with their Apple ID, because that is the identity
  they already have.
- **An admin** wants certainty that the daughter cannot delete a transaction, and
  that certainty not to rest on the app's buttons.
- **An admin** wants to still get in when Apple is unreachable or the membership
  has lapsed.

## Requirements

### Identity

- **R1.** An admin must create a member's account — an email address and an
  initial password — before that member can sign in. There is no self-service
  sign-up: a person cannot bring themselves into existence as a member, only an
  admin can, the same boundary R6c already draws for a Telegram id.
- **R1d.** The password an admin sets at R1 is **temporary**: it must be marked
  as needing a change, and the account must reach nothing until the member
  changes it at their first sign-in — the same rule spec 0001's bootstrap
  admin already follows (R14e), extended to every member an admin creates.
- **R1a.** A member must be able to sign in with **email and password** from any
  device, with nothing bought and nothing enrolled beyond the account R1 already
  created. This is the method a new member is onboarded with.
- **R1b.** A member must be able to sign in with their **Apple ID** once the
  membership exists — and that sign-in must attach to an account that already
  exists, never create one.
- **R1c.** The **first** Apple sign-in for a member must attach automatically,
  matched on the email address the admin gave that account at R1 against the
  email Apple reports at that first grant — no separate admin confirmation step
  for this one link, since the admin already performed the equivalent act by
  creating the account. Every sign-in after that first attach matches on Apple's
  stable subject identifier (R4) exactly as any other method does, never on
  email again: Hide My Email, or a changed Apple ID email, must not break a link
  already made (A7).
- **R2.** A member must be able to authenticate with a **passkey** using the
  biometric sensor on their own device, without a password.
- **R3.** Every member must hold at least two methods, and **an admin must hold at
  least one that is not a password** — a password alone must not reach the
  administrative surfaces.
- **R3a.** Adding a method must attach it to the signed-in member's account, so a
  person never ends up with two identities. Apple's link must store its subject
  identifier, not an email address.
- **R3b.** There must be **no self-service password reset**: an admin resets a
  password and the reset is audited. No outbound email dependency is introduced.
- **R3c.** The password endpoint must be rate-limited and must lock out on
  repeated failure.
- **R4.** Accounts must be matched on the identity provider's stable subject
  identifier, never on an email address. An email address is a login identifier
  and may change without changing who someone is.
- **R5.** A member must be able to hold passkeys on several devices, and an admin
  must be able to revoke one.
- **R6.** Each admin must hold a factor that does not depend on a single device.

### Roles and authorisation

- **R6a.** A member must be an account of ours, with the identity provider's
  subject and the Telegram user id as **links** to it, not as the identity itself
  (ADR 0030).
- **R6b.** Every member must have an account, admins and member alike.
- **R6c.** An admin must link a member's Telegram id to their account. An unlinked
  Telegram id must reach nothing, and the linking flow must not let a member
  claim an account by self-service.
- **R6d.** Attribution must reference the member, never a channel id, so a
  re-linked Telegram account leaves history intact.
- **R6e.** Break-glass access must be two independent routes, neither depending on
  the identity provider: an SSH key per admin, and the provider's console. Both
  admins hold both.
- **R7.** Roles must be `admin` and `member`, with two admins and one member
  today, and the role must be a property of the member rather than of a person.
- **R8.** Authorisation must be enforced by row-level security in the database, so
  that the same rules apply through the bot, the app, the data API and a direct
  database session.
- **R9.** Every member must be able to read the whole ledger.
- **R10.** Only an admin must be able to change or delete a recorded transaction,
  merge merchants, reverse an import, or change membership.
- **R11.** Any member must be able to change the category or project attribution
  of any transaction.
- **R12.** Any member must be able to confirm a record they captured while it is
  unconfirmed, and to correct it while it is unconfirmed.
- **R13.** No member may write a raw posting through the data API under any role.
- **R14.** An unauthenticated request must be able to read nothing at all.

### Bootstrapping the first admin

- **R14a.** There must be a **scaffold command** that creates the first admin
  account from environment variables — email and initial password — since every
  other account and every channel link requires an admin to already exist. It must
  work identically on a fresh local and a fresh rented deployment, and leave no
  standing mechanism behind.
- **R14b.** The scaffold must refuse to run once any account exists, and the fact
  that it ran must be recorded in the audit log.
- **R14c.** The scaffolded password must be marked as initial and must be changed
  at first sign-in; until it is, that account must reach nothing beyond the change
  itself.

### The path

- **R15.** The data API must accept only tokens issued by the identity provider,
  must verify them, and must adopt the role and member identifier they carry.
- **R15a.** The token must carry **our own member identifier**, not only the
  provider's subject: the identity provider stores the member id as an attribute
  on the account and templates it into the token, so row-level security keys on
  one identifier everywhere. A token without a resolvable member id must be
  rejected rather than treated as anonymous.
- **R15b.** The database roles must be enumerated, with the privileges of each,
  and no role may hold more than it needs:

  | Role | Who uses it | May |
  |---|---|---|
  | `anon` | Unauthenticated requests | Nothing at all |
  | `hh_member` | A signed-in member, via the data API | Read everything; write classification, confirmations of their own captures, and wishes |
  | `hh_admin` | A signed-in admin, via the data API | The above, plus corrections, deletions, merges, imports and structural changes |
  | `hh_agent` | n8n, server-side | Insert captures and transactions, always with an acting member set; never read secrets, never bypass the postings invariant |
  | `hh_report` | Read-only reporting | Select on views only |
  | `authenticator` | PostgREST's own connection | Nothing but switching into the roles above |

- **R15c.** A write by any role without an acting member set must **fail**, not
  default to a system actor — the audit log's value is that the actor is never
  unknown (ADR 0008).
- **R16.** The app must hold no credential of its own and must be trusted with
  nothing: it is a static bundle in a browser.
- **R16a.** The browser must never receive a database token. Requests from the app
  to the data API go through the reverse proxy, which — having already
  authenticated the session — **adds the Authorization header itself** from the
  member's identity. A bearer token in browser storage would be a credential in
  the one place the design says there is none, reachable by any script that gets
  into the page.
- **R16b.** The data API must not be reachable except through that proxy path, so
  a token cannot be replayed from elsewhere.
- **R16c.** There must be a documented way to obtain a token **locally**, so
  row-level security can be exercised by hand as well as by the suite — without
  weakening the rule that the browser never holds one.
- **R17.** Each protected component must work behind the boundary without
  requiring any feature its free self-hosted edition gates.
- **R17b.** **Every** surface goes through our own single sign-on — present ones
  and any added later. A component that cannot sit behind the boundary is not
  deployed, and no surface may be reachable by its own port or its own login
  alone. n8n's inner password is a second layer behind the boundary, never a way
  around it.
- **R17c.** The boundary runs **locally too**, with the same forward
  authentication and the same token path. A local mode that bypassed sign-in would
  leave the most security-critical path in the system exercised only in
  production.
- **R17a.** One sign-in must admit an admin to **every** administrative surface.
  Where a component keeps a session of its own, it must either be configured to
  trust the boundary, or its remaining login must be documented as a known second
  step with its credential in the shared vault (ADR 0024). The intended handling
  per surface:

  | Surface | Its own session |
  |---|---|
  | The household app | None by design; authorisation is row-level security (ADRs 0007, 0014) |
  | PostgREST | None; it verifies the token the boundary issued |
  | Uptime Kuma | Its own authentication **disabled**, so the boundary is the only gate |
  | The identity provider's own admin | Authenticated by itself, which is self-referential: if it is misconfigured, the boundary and its admin are lost together. That is exactly what the break-glass path exists for (R6e), and why its configuration is blueprints in this repository rather than clicks (ADR 0010) |
  | n8n | **Keeps its owner login.** Community edition has no SSO (ADR 0001), so reaching the editor is one sign-in at the boundary plus n8n's own password. This is the single exception, and it is a password both admins hold rather than a second identity |

  A component that can neither trust the boundary nor have its login documented
  this way is not deployed until it can.
- **R18.** A break-glass path must let either admin reach the host and the
  database when the identity provider itself is unavailable.

## Scope

**In scope:** the identity provider's configuration as blueprints, Apple as a
federated source, passkey enrolment, the two roles, row-level security policies
for the tables that exist so far, the data API's token verification, the
break-glass path, and the tests that prove all of it by impersonation.

**Out of scope (and why):**
- The ledger's own tables and policies for them (spec 0003) — the policies here
  cover what exists, and each later slice brings its own.
- Screens (spec 0006). This slice proves the path, not the interface.
- Per-member visibility limits. ADR 0016 decided everyone reads everything.

## Acceptance criteria

- [ ] **A1.** Given an admin has created a member's account (an email and an
      initial password, nothing bought) and no device enrolled yet, when that
      member signs in with the email and password, then they reach the surfaces
      their role allows — onboarding depends on an admin's one action, never a
      purchase, and self-registration is refused if attempted.
- [ ] **A1a.** Given a member whose account an admin created, when Apple reports
      an email at first sign-in matching that account's email, then the Apple
      identity attaches to it automatically — no second admin step for this link.
- [ ] **A1b.** Given a member whose account an admin just created, when they sign
      in with the temporary password before changing it, then they reach nothing
      until they set their own password; a second sign-in with the same
      temporary password fails identically.
- [ ] **A2.** Given that member signed in, when they enrol a passkey and later an
      Apple ID, then both attach to the **same** account and no second account
      exists.
- [ ] **A3.** Given an admin, when their account holds only a password, then the
      administrative surfaces are refused until a second, non-password method is
      enrolled.
- [ ] **A4.** Given repeated failed password attempts, when the threshold is
      crossed, then the account locks out and the attempt is logged.
- [ ] **A5.** Given a member who has forgotten their password, when a reset is
      attempted, then no email is sent by the system and an admin performs the
      reset, which appears in the audit record.
- [ ] **A6.** Given a member with an Apple ID, when they sign in with Apple and
      then open a second protected surface, then they reach it without signing in
      again.
- [ ] **A7.** Given a member who signed in with Apple using Hide My Email, when
      they sign in a second time, then they land on the same account rather than a
      new one.
- [ ] **A8.** Given a member enrolled with a passkey on an iPhone, when they open
      the household surface, then they authenticate with the biometric alone.
- [ ] **A9.** Given the Apple source is deliberately disabled, when an admin signs
      in with their passkey, then they still reach the administrative surfaces.
- [ ] **A10.** Given a member whose role is `member`, when they request an
      administrative surface, then access is refused.
- [ ] **A11.** Given a `member` role, when a delete of a recorded transaction is
      attempted **directly against the database**, then it fails — proven by
      impersonation in the test suite, not through the bot.
- [ ] **A12.** Given a `member` role, when a category or project change is
      attempted, then it succeeds.
- [ ] **A13.** Given a `member` role, when an insert of a raw posting is attempted
      through the data API, then it fails.
- [ ] **A14.** Given no token, when any data endpoint is requested, then nothing is
      returned — for every exposed view, enumerated.
- [ ] **A15.** Given a token with a tampered role claim, when a request is made,
      then it is rejected.
- [ ] **A16.** Given an expired token, when a request is made, then it is
      rejected.
- [ ] **A17.** Given a member marked inactive, when they attempt any sign-in, then
      it fails and their existing sessions do not survive.
- [ ] **A18.** Given a Telegram account not linked to any member, when it messages
      the bot, then nothing is recorded, the reply reveals nothing, and the attempt
      is logged.
- [ ] **A19.** Given an admin linking a Telegram id to a member, when that member
      then captures an expense, then it is attributed to the member — and when the
      link is later moved to another account, past transactions keep their original
      submitter.
- [ ] **A20.** Given a member with no channel linked, when they sign into the app,
      then they reach it — an account exists before a channel does.
- [ ] **A21.** Given a fresh deployment with no accounts, when the documented
      bootstrap path is followed once, then a first admin exists and can sign in —
      and when it is attempted a second time, it is refused.
- [ ] **A22.** Given a token carrying a provider subject but no resolvable member
      id, when a data request is made, then it is rejected — not silently treated
      as anonymous.
- [ ] **A23.** Given each enumerated database role, when the privileges it
      actually holds are inspected, then they match R15b exactly — checked against
      the database, not against the intention.
- [ ] **A24.** Given the agent's role, when an insert is attempted with no acting
      member set, then it fails.
- [ ] **A25.** Given a member using the app, when the browser's storage, cookies
      and network requests are inspected, then **no database token is present in
      the page** — the Authorization header is added by the proxy and never
      visible to scripts.
- [ ] **A26.** Given the data API's address, when it is requested directly,
      bypassing the proxy, then it is unreachable.
- [ ] **A27.** Given the identity provider stopped, when an admin follows the
      break-glass procedure, then they reach the host and the database — performed
      once, recorded.
- [ ] **A28.** Given a member with passkeys on two devices, when an admin revokes
      one, then that device can no longer sign in and the other still can.
- [ ] **A29.** Given an admin's factor that is not bound to one device, when their
      phone is treated as lost, then they can still sign in.
- [ ] **A30.** Given each member in turn, when the whole ledger is read, then all
      of it is returned — everyone reads everything, and that is asserted rather
      than assumed from the absence of a filter.
- [ ] **A31.** Given an unconfirmed record captured by a member, when that member
      confirms it, then it becomes confirmed; and when they attempt the same on
      another member's record, it fails.
- [ ] **A32.** Given the app's built bundle, when it is searched, then it contains
      no credential, key or database connection string.
- [ ] **A33.** Given each protected component, when reached through the boundary,
      then it is usable with no paid-tier feature enabled, demonstrated per
      component.
- [ ] **A34.** Given an admin who has signed in once, when they open each
      administrative surface in turn, then none asks them to authenticate again —
      except n8n, which asks for its own password exactly once per session, as
      documented in R17a. Any other surface asking again is a defect.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| Apple returns no email on a later sign-in | Irrelevant: matching is on the subject identifier |
| A member has two Apple IDs | Two identities; an admin links or refuses deliberately, never automatically |
| The public hostname changes | Passkeys must be re-enrolled; documented, because it is otherwise discovered at the worst moment |
| A member loses their only device | An admin revokes and re-enrols; the member keeps Apple sign-in meanwhile |
| The identity provider is misconfigured into locking everyone out | Break-glass path, for either admin |
| A policy is missing on a new table | Default deny: a table with no policy must be unreachable, not open |
| A token from a different audience | Rejected |
| The scaffold's initial password never changed | The account reaches nothing until it is changed, so an unrotated bootstrap credential is inert rather than a standing key |
| The bootstrap path left enabled after first use | Refused on a second attempt, which is an acceptance criterion of its own; a standing self-service route to an admin account is the worst possible hole |
| A component that ships with its own login enabled by default | Either disabled so the boundary is the only gate, or documented in R17a — never left as an undocumented second password |

## Ergonomic cost

- **Who does more work:** an admin, once per member and once per device, for
  enrolment. Nobody afterwards — the point is that signing in stops being work.
- **What queue it creates:** none. Revocations are events, not a backlog.
- **What it interrupts:** nothing routine. A failed sign-in is the member's own
  immediate feedback.
- **If nobody touches it for a month:** nothing degrades, with one exception —
  the Apple membership lapses annually and would silently remove one method.
  Passkeys keep working, and the lapse is a monitored expiry, not a surprise.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **Sign-in latency:** a biometric sign-in completes in seconds, on mobile data.
- **Default deny:** every new table and view is unreachable until a policy grants
  it, so a forgotten policy fails closed.
- **No secret in the browser**, ever.

## Open questions

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | Is the Apple Developer Program membership held, or will it be bought? It gates only R1b/R1c, and no longer blocks anything: email and password onboards everyone today (ADR 0032) | nothing | open |
| Q2 | The daughter's Apple ID — a child account under Family Sharing, and does it have the two-factor authentication Apple requires? Only needed if and when Apple sign-in is added for her | nothing | open |

## Related

- ADRs: 0014, 0015, 0016, 0021, 0023, 0024, 0026, 0030, 0032, 0034, 0041
- Specs: 0001 (must be done first), 0003, 0006
