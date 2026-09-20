---
id: 0006
title: Web access via a self-hosted identity provider, with Apple ID sign-in and passkeys as the fallback
status: superseded
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: [0032]
---

# ADR 0006 - Web access via a self-hosted identity provider, with Apple ID sign-in and passkeys as the fallback

> **Superseded by [ADR 0032](./0032-sign-in-methods-password-passkeys-and-apple.md).**
> Email and password joins passkeys and Apple sign-in, which takes the Apple
> Developer membership off the critical path of onboarding. The self-hosted
> identity provider and the proxy as the single boundary are unchanged, and the
> reasoning below stands as written.

## Context

Two audiences need to log in to a web surface, and they differ only in what they
are allowed to reach, so one authentication boundary serves both:

- The household (ADR 0007) uses the mobile app for trends and reports. Two of
  the three members will use it, and neither will tolerate a password prompt.
- The owner alone uses the n8n editor and the back-office grid. Whoever reaches
  the n8n editor reaches the ledger, the OpenRouter key and the bot token, so
  this side needs to be stronger than a shared password.

The household is entirely on Apple devices, so "sign in with Apple ID" was the
first thought. Three facts shape the answer:

1. n8n community edition has no single sign-on, because SAML and OIDC login are
   enterprise features and ADR 0001 commits us to not depending on those. Single
   sign-on therefore cannot be configured *inside* n8n and has to sit in front
   of it.
2. Sign in with Apple costs money but little labour. As an OIDC provider it
   needs a paid Apple Developer Program membership (99 USD/year) and a Services
   ID with a verified domain and return URL. Apple's client secret is a JWT that
   Apple refuses if it expires more than six months out, but we give authentik
   the Services ID, Team ID, Key ID and the `.p8` private key, and authentik
   mints that JWT itself, so nobody rotates it by hand. The tunnel from ADR 0002
   supplies the publicly reachable HTTPS return URL.
3. Passkeys give the same Apple-native experience without any of that: Touch ID
   and Face ID, synced across the household's devices through iCloud Keychain,
   with no yearly fee, no secret to rotate and no dependency on Apple's servers
   at sign-in time.

Two different things both get called "Apple ID login", and the question keeps
coming up, so here is the difference. **A passkey** is a credential created in
and held by the device, synced between the household's devices by iCloud
Keychain, which is what their Apple ID does here, and unlocked with Face ID or
Touch ID; our identity provider is the only party that verifies it, and it works
on any iPhone or Mac on a current OS, costs nothing and is available today. Sign
in with Apple is an OIDC federation where Apple authenticates the person and we
trust Apple's answer, and that is the option with the 99 USD/year membership,
the verified domain and the rotating JWT secret. In practice they are not
alternatives, since both end up gated by Face ID on the same device, and the
passkey gets there without the paperwork.

## Decision

We put a **self-hosted identity provider (Authentik)** in front of every
administrative and household surface, and the reverse proxy enforces forward
authentication. Each tool keeps its own login as a second, inner layer, and that
inner login is never the boundary. Ten rules follow:

- Sign in with Apple is the login method, configured once in authentik as a
  federated source. Because authentik is the single boundary in front of n8n,
  the household app and anything we add later, one Apple source gives single
  sign-on into every panel, and it does so without any tool's paid SSO tier.
- Accounts are linked on Apple's stable subject identifier and never on email,
  because Apple returns an email address only on the first authorization and it
  can be a Hide My Email relay address that differs per service. Keying on email
  would silently create a second account or fail to match.
- Passkeys (WebAuthn) stay as a parallel method and are the break-glass path.
  We keep them not for the sake of a second mechanism but because an Apple-only
  login would lock the admins out of their own ledger if the membership lapsed
  on renewal or Apple's service went unreachable. Every member enrolls a passkey
  as well as Apple sign-in.
- The `.p8` key can be downloaded exactly once, so it goes into the owner's
  password manager alongside the other secrets (ADR 0009). If it is lost, we
  generate a new key in the Apple Developer portal.
- The Apple ID must have two-factor authentication enabled, which Apple requires
  for Sign in with Apple, and all the household's accounts already do.
- Every member who uses the app gets an account, in one group per audience:
  `household` reaches the mobile app only, and `admin` reaches n8n and the
  back-office grid as well. The daughter's and the partner's accounts are never
  in `admin`.
- Passkeys are enrolled per device and a member can hold several. The owner
  keeps a second factor that does not depend on one phone, either a hardware key
  or a recovery code in the password manager, because losing the only passkey
  means losing administrative access.
- A passkey is bound to the domain it was created for, so we use the same
  hostname on the VPS and on the home server. If the domain ever changes, every
  member re-enrolls, and the migration slice names that as a task so it does not
  arrive as a surprise.
- Authentik runs as a container in the same Compose file (ADR 0002), so it
  survives the move to the home server.
- The proxy is the boundary on purpose. n8n's own single sign-on is an
  enterprise feature (ADR 0001), and the household app has no login of its own,
  since it is a static bundle whose authorization is row-level security in the
  database (ADRs 0007, 0014). Forward authentication at the proxy serves both
  without a paid tier anywhere. We prove what each component needs from its own
  session, and how the token reaches PostgREST, in the bootstrap slice, before
  any screen binds to it.

## Alternatives

| Option | Why rejected |
|---|---|
| Sign in with Apple as the *only* login, with no passkeys | Makes a 99 USD yearly renewal and a third party's availability load-bearing for reaching the household's own books. A missed renewal email would be enough to lock the owner out |
| Passkeys only, no Apple ID | Technically enough and free. We rejected it because an admin wants Apple sign-in across the panels, and under this architecture that costs one source configuration plus the membership |
| n8n enterprise SSO | Contradicts ADR 0001's commitment to the community edition, and pays for a feature a proxy provides |
| n8n's built-in owner login alone | One password would protect the ledger, the bot token and the model key. Too thin a boundary, and no second factor |
| oauth2-proxy with Apple directly | Lighter than Authentik, but Apple's JWT client secret and form-POST callback make it the awkward case for generic OIDC proxies, and it leaves nowhere to manage passkeys |
| Keycloak | Equally capable and it also supports Apple as a source, but it is heavier to operate than Authentik for a household with one admin |
| VPN-only access (WireGuard, Tailscale) to the admin surfaces | Genuinely strong, and worth adding as an *extra* layer for the admin surfaces once the home server exists. We rejected it as the only method because it protects the network path and not the application, and because the household app has to open from a phone on any network without a VPN profile in the way |


## Consequences

We gain four things:

- One Apple sign-in reaches every panel, configured in one place, with no tool's
  paid SSO tier involved.
- The household gets Face ID or Touch ID either way, through Apple's flow or
  through a passkey, which is the only login they will accept for a phone app
  they open in a shop.
- Nobody rotates a client secret by hand, because authentik signs Apple's JWT
  from the `.p8` key itself.
- We can add Apple ID later as a login option without redesigning anything.

We accept six costs in return:

- We run, patch and back up one more container, which is the main operational
  cost of this decision.
- The membership costs 99 USD a year indefinitely, and a renewal that nobody can
  miss. Keeping passkeys enrolled covers the miss better than remembering to
  renew.
- Apple's availability sits in the login path, which is why the fallback is not
  optional.
- A misconfigured authentik can lock the owner out of his own system, so we need
  a documented break-glass path: direct n8n access from the host.
- Passkeys depend on the Apple ecosystem's sync, so a household that changes
  platforms, or a domain that changes, means enrolling again.
- A member who loses their only device loses access until an admin resets it.

Little gets harder to change later, because authentication lives in the proxy
layer, so swapping the identity provider or adding Apple ID is a change in one
place.
