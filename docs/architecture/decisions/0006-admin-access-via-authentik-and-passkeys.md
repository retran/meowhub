---
id: 0006
title: Web access via a self-hosted identity provider, with Apple ID sign-in and passkeys as the fallback
status: superseded
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: [0032]
---

# ADR 0006 — Web access via a self-hosted identity provider, with Apple ID sign-in and passkeys as the fallback

> **Superseded by [ADR 0032](./0032-sign-in-methods-password-passkeys-and-apple.md).**
> Email and password joins passkeys and Apple sign-in, which takes the Apple
> Developer membership off the critical path of onboarding. The self-hosted
> identity provider and the proxy as the single boundary are unchanged; the
> reasoning below stands as written.

## Context

Two different audiences need to log in to a web surface:

- **The household** (ADR 0007): the mobile app for trends and reports. Two of the
  three members will use it, and neither will tolerate a password prompt.
- **The owner alone**: the n8n editor and the back-office grid. Whoever reaches
  the n8n editor reaches the ledger, the OpenRouter key and the bot token, so
  this needs to be stronger than a shared password.

Both are served by one authentication boundary; they differ only in what they are
authorised to reach.

The household is entirely on Apple devices, so "sign in with Apple ID" was the
natural first thought. Three facts shape the answer:

1. **n8n community edition has no SSO.** SAML and OIDC login are enterprise
   features, and ADR 0001 commits us to not depending on those. So single
   sign-on cannot be configured *inside* n8n; it has to sit in front of it.
2. **Sign in with Apple costs money but not much labour.** As an OIDC provider
   it requires a paid Apple Developer Program membership (99 USD/year) and a
   Services ID with a verified domain and return URL. Apple's client secret is a
   JWT it refuses if it expires more than six months out, but authentik is given
   the Services ID, Team ID, Key ID and the `.p8` private key and mints that JWT
   itself, so there is **no manual rotation**. The publicly reachable HTTPS
   return URL is satisfied by the tunnel from ADR 0002.
3. **Passkeys give the Apple-native experience without any of that.** Touch ID
   and Face ID, synced across the household's devices through iCloud Keychain,
   no yearly fee, no secret rotation, no dependency on Apple's servers at
   sign-in time.

It is worth separating two things that both get called "Apple ID login", because
the question keeps coming up:

- **A passkey** is a credential created in and held by the device, synced between
  the household's devices by iCloud Keychain — which is what their Apple ID is
  doing here — and unlocked with Face ID or Touch ID. Our identity provider is
  the only party verifying it. This works on any iPhone or Mac on a current OS,
  costs nothing, and is available immediately.
- **Sign in with Apple** is an OIDC federation where Apple authenticates the
  person and we trust Apple's answer. That is the option with the 99 USD/year
  membership, the verified domain and the rotating JWT secret.

They are not alternatives to each other in practice: both end up gated by Face ID
on the same device. The passkey gets there without the paperwork.

## Decision

Put a **self-hosted identity provider (Authentik)** in front of every
administrative and household surface, with the reverse proxy enforcing forward
authentication. Each tool's own login remains as a second, inner layer; it is
never the boundary.

- **Sign in with Apple is the login method**, configured once in authentik as a
  federated source. Because authentik is the single boundary in front of n8n, the
  household app and anything added later, one Apple source gives single sign-on
  into every panel — and it does so without needing any tool's paid SSO tier,
  which is the other reason the boundary sits at the proxy: n8n's SSO is an
  enterprise feature, and the household app has no login of its own by design
  (ADR 0007).
- **Accounts are linked on Apple's stable subject identifier, never on email.**
  Apple returns an email address only on the first authorisation, and it may be a
  Hide My Email relay address that differs per service. Keying on email would
  silently create a second account or fail to match.
- **Passkeys (WebAuthn) are kept as a parallel method, and they are the
  break-glass path.** This is not belt-and-braces for its own sake: if the
  membership lapses on renewal, or Apple's service is unreachable, Apple-only
  login would lock the admins out of their own ledger. Every member enrols a passkey
  in addition to Apple sign-in.
- **The `.p8` key is downloadable exactly once** and goes into the owner's
  password manager alongside the other secrets (ADR 0009). Losing it means
  generating a new key in the Apple Developer portal.
- **The Apple ID must have two-factor authentication enabled**, which Apple
  requires for Sign in with Apple; all the household's accounts already do.
- **Every member who uses the app gets an account**, and one group per audience:
  `household` reaches the mobile app only; `admin` additionally reaches n8n and
  the back-office grid. The daughter's and partner's accounts are never in
  `admin`.
- **Passkeys are enrolled per device**, and a member can hold several. The owner
  keeps a second factor that does not depend on one phone — a hardware key or a
  recovery code in the password manager — because losing the only passkey means
  losing administrative access.
- **The domain is part of the credential.** A passkey is bound to the domain it
  was created for, so the same hostname must be used on the VPS and on the home
  server. If the domain ever changes, every passkey is re-enrolled — this is a
  named task in the migration slice, not a surprise.
- Authentik runs as a container in the same Compose file (ADR 0002), so this
  survives the move to the home server.
- **The proxy is the boundary, deliberately.** n8n's own SSO is an enterprise
  feature (ADR 0001), and the household app has no login of its own — it is a
  static bundle whose authorisation is row-level security in the database
  (ADRs 0007, 0014). Forward authentication at the proxy serves both without a
  paid tier anywhere. What each component requires of its own session, and how
  the token reaches PostgREST, is proven in the bootstrap slice before any screen
  binds to it.

## Alternatives

| Option | Why rejected |
|---|---|
| Sign in with Apple as the *only* login, with no passkeys | Makes a 99 USD yearly renewal and a third party's availability load-bearing for reaching the household's own books. A missed renewal email would be enough to lock the owner out |
| Passkeys only, no Apple ID | Technically sufficient and free. Rejected because an admin wants Apple sign-in across the panels, and under this architecture it costs one source configuration plus the membership |
| n8n enterprise SSO | Contradicts ADR 0001's commitment to the community edition, and pays for a feature a proxy provides |
| n8n's built-in owner login alone | A single password protects the ledger, the bot token and the model key. Too thin a boundary, and no second factor |
| oauth2-proxy with Apple directly | Lighter than Authentik, but Apple's JWT client secret and form-POST callback make it the awkward case for generic OIDC proxies, and there is then nowhere to manage passkeys |
| Keycloak | Equally capable and also supports Apple as a source, but heavier to operate than Authentik for a household of one admin |
| VPN-only access (WireGuard, Tailscale) to the admin surfaces | Genuinely strong and worth considering as an *additional* layer for the admin surfaces once the home server exists. Rejected as the sole mechanism because it protects the network path, not the application, and because the household app must open from a phone on any network without a VPN profile in the way |


## Consequences

**Good:**
- One Apple sign-in reaches every panel, configured in one place, with no tool's
  paid SSO tier involved.
- Face ID or Touch ID either way — through Apple's flow or through a passkey —
  which is the only login the household will accept for a phone app they open in
  a shop.
- No manual client-secret rotation, because authentik signs Apple's JWT from the
  `.p8` key itself.
- Apple ID can be added later as a login option without redesigning anything.

**Bad, and the price we accept:**
- One more container to run, patch and back up. This is the main operational
  cost of the decision and it is real.
- 99 USD a year, indefinitely, and a renewal that must not be missed — mitigated
  by passkeys remaining enrolled rather than by remembering to renew.
- A dependency on Apple's availability in the login path, which is why the
  fallback is not optional.
- Authentik misconfiguration can lock the owner out of his own system, so a
  documented break-glass path (direct n8n access from the host) is required.
- Passkeys are tied to the Apple ecosystem's sync; a household that changes
  platforms, or a domain that changes, means re-enrolling.
- A member who loses their only device loses access until an admin resets it.

**What becomes harder to change later:**
- Little. The proxy layer is where authentication lives, so swapping the identity
  provider or adding Apple ID is a change in one place.
