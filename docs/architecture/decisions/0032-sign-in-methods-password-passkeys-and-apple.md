---
id: 0032
title: Three sign-in methods — email and password, passkeys, and Apple linked later
status: accepted
date: 2026-09-12
deciders: owner
supersedes: [0006]
superseded-by: []
---

# ADR 0032 - Three sign-in methods: email and password, passkeys, and Apple linked later

## Context

Everyone in the household has an account, and we own that account: the identity
provider's subject and the Telegram id are links to it (ADR 0030). What's left to
decide is how a person proves they are that account.

Two parts of the previous answer didn't hold up. Apple sign-in is a purchase,
because it needs a paid developer membership, so it put 99 USD and a domain
verification on the critical path of letting three people in. And a passkey binds
to the device at the moment of enrolment, which works well once established and
leaves nothing to fall back on for a member on a borrowed laptop, before their
first enrolment, or after losing their only phone.

Neither method covers the boring universal case that needs no purchase and no
particular device.

## Decision

We offer three methods, and all three are links to one member account.

1. Email and password, available from day one for every member. This is the
   floor: it works on any device, costs nothing to buy, and is what we onboard a
   new member with.
2. Passkeys (WebAuthn), the everyday method on the household's Apple hardware,
   through Face ID or Touch ID and synced by iCloud Keychain. Every member enrols
   one on their own device after first signing in.
3. Sign in with Apple, added once the membership exists, as one more link to an
   account that already exists. It never creates an account, and nothing depends
   on it.

Adding a method never creates a second identity: a member signs in with what they
have and attaches the next method to that account. The link stores Apple's
subject identifier rather than an email address, because Apple returns an address
only on the first authorisation and it can be a relay (ADR 0030).

### Rules that keep the weakest method from being the weak point

A password is the weakest of the three, so five rules stop it setting the
system's floor.

An admin holds at least two methods, at least one of which isn't a password, so a
password alone never reaches the administrative surfaces. We rate-limit the
password endpoint and lock it out after repeated failure, at the edge as well as
in the provider (spec 0001). The identity provider enforces the password policy
and stores the passwords, which never enter our schema.

We deliberately offer no self-service password reset, because a reset flow needs
outbound email, and that would mean running an SMTP dependency, paying for it,
and placing it under the residency direction (ADR 0028) for three people who live
in the same house. Instead an admin resets a password, hands it over in person,
and the reset is audited. If the household ever needs remote resets, adding SMTP
is a small, separate decision.

Email is a login identifier and not the identity, so changing it changes a
credential rather than who someone is, and no attribution follows it.

## Alternatives

| Option | Why rejected |
|---|---|
| Apple ID and passkeys only | What ADR 0006 decided. It puts a purchase on the critical path of onboarding, and leaves a member with no way in before their first passkey exists or after losing the device that held it |
| Email and password only | Simplest, and it makes the daily sign-in a password prompt on a phone in a shop - which is the friction that stops people using the app at all |
| Passwordless email links ("magic links") | Pleasant, and it needs the SMTP dependency this decision exists to avoid, and it makes the mail account a single point of access to the household's books |
| Self-service password reset by email | The expected behaviour for a product, and disproportionate here: an SMTP service to operate and place under residency, so that three people in one house can avoid asking each other |
| A shared household password | One credential, no attribution, and a leak that cannot be scoped to a person |
| Delaying everything until the Apple membership is bought | Ties three people's access to a purchase nobody needs to make yet |

## Consequences

Good:
- Onboarding needs no purchase, because Apple's membership moves off the critical
  path and becomes an improvement we can make later.
- A member always has a way in: a password when the device is unfamiliar or the
  passkey is gone, and biometrics the rest of the time.
- Adding Apple later costs one link on an existing account, so it disturbs no
  history, no attribution, and no membership.
- We add no infrastructure: no SMTP, no mail domain, no deliverability to manage.

Bad, and the price we accept:
- A password is the weakest method, and it now exists. That's why admins hold a
  second, non-password method and why we rate-limit the endpoint, but the floor
  of the system's security is now a password policy instead of a hardware-backed
  key.
- Without self-service reset, a forgotten password becomes an errand for an
  admin. That works for one household, and it's the first thing to revisit if
  anyone travels alone for long.
- Three methods mean three paths to test and to revoke (ADR 0026), and a member
  can now carry a stale password nobody remembers setting.

Nothing becomes harder to change later. All three methods are links on the same
account, so we can add or withdraw one without touching identity, attribution, or
the ledger, which is exactly what ADR 0030 bought.
