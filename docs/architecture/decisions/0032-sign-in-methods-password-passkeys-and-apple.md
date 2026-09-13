---
id: 0032
title: Three sign-in methods — email and password, passkeys, and Apple linked later
status: accepted
date: 2026-09-12
deciders: owner
supersedes: [0006]
superseded-by: []
---

# ADR 0032 — Three sign-in methods: email and password, passkeys, and Apple linked later

## Context

Everyone in the household has an account, and the account is ours — the identity
provider's subject and the Telegram id are links to it (ADR 0030). What remains is
how a person proves they are that account.

Two things about the previous answer did not hold up. **Apple sign-in is a
purchase**: it needs a paid developer membership, so it put 99 USD and a domain
verification on the critical path of letting three people in. And **a passkey is
device-bound at the moment of enrolment**: excellent once established, and nothing
to fall back on for a member on a borrowed laptop, or before their first
enrolment, or after losing their only phone.

What is missing is the boring universal method that needs no purchase and no
particular device.

## Decision

**Three methods, all of them links to one member account.**

1. **Email and password** — available from day one, for every member. This is the
   floor: it works on any device, needs nothing bought, and is what a new member
   is onboarded with.
2. **Passkeys (WebAuthn)** — the everyday method on the household's Apple
   hardware: Face ID or Touch ID, synced through iCloud Keychain. Every member
   enrols one on their own device after first signing in.
3. **Sign in with Apple** — added when the membership exists, as **an additional
   link to an account that already exists**. It never creates an account, and
   nothing depends on it.

Adding a method never creates a second identity: a member signs in with what they
have and attaches the next method to that account. Apple's subject identifier is
what the link stores, not an email address — Apple returns an address only on the
first authorisation and it may be a relay (ADR 0030).

### Rules that keep the weakest method from being the weak point

- **Admins must hold at least two methods, and at least one that is not a
  password.** A password alone must not reach the administrative surfaces.
- **The password endpoint is rate-limited and locks out on repeated failure**, at
  the edge as well as in the provider (spec 0001).
- **Password policy is enforced by the identity provider**, and passwords are
  stored only there — never in our schema.
- **There is no self-service password reset, and that is deliberate.** A reset
  flow needs outbound email, which would mean an SMTP dependency to run, pay for
  and place under the residency direction (ADR 0028) — for three people who live
  in the same house. **An admin resets a password and hands it over in person**,
  and the reset is audited. If the household ever needs remote resets, adding
  SMTP is a small, separate decision.
- **Email is a login identifier, not the identity.** Changing it changes a
  credential, not who someone is, and no attribution follows it.

## Alternatives

| Option | Why rejected |
|---|---|
| Apple ID and passkeys only | What ADR 0006 decided. It puts a purchase on the critical path of onboarding, and leaves a member with no way in before their first passkey exists or after losing the device that held it |
| Email and password only | Simplest, and it makes the daily sign-in a password prompt on a phone in a shop — which is the friction that stops people using the app at all |
| Passwordless email links ("magic links") | Pleasant, and it needs the SMTP dependency this decision exists to avoid, and it makes the mail account a single point of access to the household's books |
| Self-service password reset by email | The expected behaviour for a product, and disproportionate here: an SMTP service to operate and place under residency, so that three people in one house can avoid asking each other |
| A shared household password | One credential, no attribution, and a leak that cannot be scoped to a person |
| Delaying everything until the Apple membership is bought | Ties three people's access to a purchase nobody needs to make yet |

## Consequences

**Good:**
- **Onboarding needs no purchase.** Apple's membership moves off the critical path
  and becomes an improvement to make later, which is where it belongs.
- A member always has a way in: password when the device is unfamiliar or the
  passkey is gone, biometrics the rest of the time.
- Adding Apple later costs one link on an existing account, so no history, no
  attribution and no membership is disturbed.
- No new infrastructure: no SMTP, no mail domain, no deliverability to manage.

**Bad, and the price we accept:**
- **A password is the weakest method, and now it exists.** It is why admins are
  required to hold a second, non-password method and why the endpoint is
  rate-limited — but the floor of the system's security is now a password policy
  rather than a hardware-backed key.
- **No self-service reset**, so a forgotten password is an errand for an admin.
  Acceptable for one household; the first thing to revisit if anyone travels
  alone for long.
- Three methods mean three paths to test and to revoke (ADR 0026), and a member
  can now have a stale password nobody remembers setting.

**What becomes harder to change later:** nothing. All three are links on the same
account, so methods can be added or withdrawn without touching identity,
attribution or the ledger — which is exactly what ADR 0030 bought.
