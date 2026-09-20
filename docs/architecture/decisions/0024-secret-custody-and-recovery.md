---
id: 0024
title: Every secret has two custodians, and recovery is rehearsed
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0024 - Every secret has two custodians, and recovery is rehearsed

## Context

The household's financial record is the asset (ADR 0004), and access to it rests
on a handful of secrets: the restic repository password, the `.env` values, the
Telegram bot token, the OpenRouter key, the Apple `.p8` signing key, the
database credentials, and the identity provider's own recovery path.

Those secrets protect the books and can also destroy them, because without the
restic password the backups stay ciphertext forever. If one person holds it, an
ordinary life event - illness, a lost phone, travel, death - becomes total loss
of a decade of household records, and no amount of encryption, offsite copying
or restore verification (ADR 0009) helps: the data would be intact and
unreadable.

The household has two adults, and both are admins (ADRs 0030, 0016). That is the
material fact this decision builds on.

## Decision

No secret in this system has one holder, and no recovery path depends on one
person.

### Custody

- Both admins hold every secret, each in their own password manager, in a shared
  vault dedicated to meowhub. A secret that exists in only one manager is a
  defect, so adding a secret means adding it to the shared vault in the same
  change.
- We keep a printed, sealed copy of the two irreplaceable secrets in the home,
  outside any computer: the restic repository password, and the offsite
  repository location and credentials. Those two are what make every other copy
  of the data readable, and everything else can be regenerated.
- The Apple `.p8` key can be downloaded only once, so we store it in the shared
  vault as soon as it's created. If it's lost, we generate a new key in the
  Apple Developer portal and revoke the old one, so it's recoverable and we
  don't seal it.
- We seal nothing that can be regenerated. Bot tokens, API keys and database
  passwords get rotated, not recovered.

### Recovery

- Each admin can perform a full restore alone, from the written procedure (spec
  0001), without the other's help and without asking anyone.
- The procedure permanently includes what to do if an admin is unavailable. It's
  a paragraph rather than a plan: where the sealed copy is, what the offsite
  repository is called, and the order of the steps.
- We rehearse recovery instead of documenting it and forgetting it. The second
  admin performs the restore once, using only the sealed copy and the written
  procedure, during the home-server migration slice, and if they can't, the
  procedure is wrong.
- Break-glass access to the host survives an identity-provider failure for both
  admins and not just one (ADR 0032).

### Rotation

- We rotate a secret when someone leaves the household (ADR 0026), when a device
  is lost, or when it might have been exposed, and not on a calendar, because
  scheduled rotation of a household's six secrets is ceremony that people would
  skip.
- Rotating a secret updates the shared vault as part of the same act, and the
  sealed copy too when it touches those two secrets.

## Alternatives

| Option | Why rejected |
|---|---|
| One custodian, as before | Turns illness or a lost device into permanent loss of the household's financial history. It's the single largest risk in the whole design, and the cheapest to remove |
| A secrets manager in the stack (Vault, Infisical) | What nexus did. It solves distribution between services and not custody between people, and it becomes one more thing whose own unseal key needs two holders, which is out of proportion for six secrets |
| Escrow with a third party or a lawyer | Proportionate to an estate rather than to a household ledger, and it puts the keys to the books outside the household |
| A "dead man's switch" that mails the secrets | Creates a standing risk of disclosure to solve a problem a sealed envelope already solves |
| Splitting the key across people (Shamir) | Cryptographically elegant and operationally fragile, because reconstruction under stress, by people who don't practise it, is how data gets lost |
| Relying on the password manager's own inheritance feature | Good, and we treat it as a supplement, because it depends on one vendor's process working at the worst possible moment while the sealed copy can be inspected today |

## Consequences

**Good:**
- The books survive any one person being unavailable, which is the point of the
  decision.
- Because each admin can restore alone, neither waits on the other for ordinary
  operations either.
- The rehearsal turns the restore procedure from a document into something we
  have proved works, and it's the same rehearsal ADR 0009 already required.

**Bad, and the price we accept:**
- A compromise now reaches twice as far: two password managers, two devices, and
  a piece of paper in the house. We trade confidentiality risk for availability
  risk deliberately, because for a household ledger availability is worth more.
- A sealed printed secret is a physical object that can be lost in a move, found
  by a visitor, or forgotten, so it needs a known place and a note in the
  procedure.
- Adding a secret now takes two steps, and the discipline will slip.
- Rotation is event-driven, so an exposure nobody notices never gets rotated
  away.

**What becomes harder to change later:** nothing technical. What we're building
here is a habit, and habits erode, which is why the rehearsal is a task in a
spec rather than a good intention.
