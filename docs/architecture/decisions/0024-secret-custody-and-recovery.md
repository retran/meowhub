---
id: 0024
title: Every secret has two custodians, and recovery is rehearsed
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0024 — Every secret has two custodians, and recovery is rehearsed

## Context

The household's financial record is the asset (ADR 0004), and access to it rests
on a handful of secrets: the restic repository password, the `.env` values, the
Telegram bot token, the OpenRouter key, the Apple `.p8` signing key, the database
credentials, and the identity provider's own recovery path.

Those secrets protect the books, and they can also destroy them. **Without the
restic password the backups are ciphertext forever.** Held by one person, that
turns an ordinary life event — illness, a lost phone, travel, death — into total
loss of a decade of household records. No amount of encryption, offsite copying or
restore verification (ADR 0009) helps: the data would be intact and unreadable.

The household has two adults, both admins (ADRs 0030, 0016). That is the material
fact this decision uses.

## Decision

**No secret in this system has one holder, and no recovery path depends on one
person.**

### Custody

- **Both admins hold every secret**, each in their own password manager, in a
  shared vault dedicated to meowhub. A secret that exists in only one manager is
  a defect, and adding a secret means adding it to the shared vault in the same
  change.
- **A printed, sealed copy of the two irreplaceable secrets** — the restic
  repository password and the offsite repository location and credentials — is
  kept in the home, outside any computer. These are the two that make every other
  copy of the data readable; everything else can be regenerated.
- **The Apple `.p8` key** is downloadable only once, so it is stored in the shared
  vault immediately on creation. If it is lost, a new key is generated in the
  Apple Developer portal and the old one revoked — recoverable, therefore not
  sealed.
- **Nothing regenerable is sealed.** Bot tokens, API keys and database passwords
  are rotated, not recovered.

### Recovery

- **Each admin can perform a full restore alone**, from the written procedure
  (spec 0001), without the other's help and without asking anyone.
- **The procedure names what to do if an admin is unavailable**, permanently
  included. It is a paragraph, not a plan: where the sealed copy is, what the
  offsite repository is called, and the order of steps.
- **Recovery is rehearsed, not documented and forgotten.** The second admin
  performs the restore once, from the sealed copy and the written procedure only,
  during the home-server migration slice. If they cannot, the procedure is wrong.
- **Break-glass access to the host** survives identity-provider failure for both
  admins, not one (ADR 0032).

### Rotation

- A secret is rotated when someone leaves the household (ADR 0026), when a device
  is lost, or when it may have been exposed — not on a calendar. Scheduled
  rotation of a household's six secrets is ceremony that would be skipped.
- **Rotation updates the shared vault as part of the act**, and the sealed copy if
  it touches those two secrets.

## Alternatives

| Option | Why rejected |
|---|---|
| One custodian, as before | Turns illness or a lost device into permanent loss of the household's financial history. The single largest risk in the whole design, and the cheapest to remove |
| A secrets manager in the stack (Vault, Infisical) | What nexus did. It solves distribution between *services*, not custody between *people* — and it becomes one more thing whose own unseal key needs two holders. Disproportionate for six secrets |
| Escrow with a third party or a lawyer | Proportionate to an estate, not to a household ledger, and it puts the keys to the books outside the household |
| A "dead man's switch" that mails the secrets | A standing risk of disclosure to solve a problem a sealed envelope solves |
| Splitting the key across people (Shamir) | Cryptographically elegant and operationally fragile: reconstruction under stress, by people who do not practise it, is how data is lost |
| Relying on the password manager's own inheritance feature | Good, and it is a supplement rather than the answer: it depends on one vendor's process working at the worst possible moment. The sealed copy is inspectable today |

## Consequences

**Good:**
- The books survive any one person being unavailable, which is the whole point.
- Two admins who can each restore alone means no waiting on the other for
  ordinary operations either.
- The rehearsal turns the restore procedure from a document into a proven
  capability — and it is the same rehearsal ADR 0009 already required.

**Bad, and the price we accept:**
- **The blast radius of a compromise doubles**: two password managers, two
  devices, and a piece of paper in the house. This is a deliberate trade of
  confidentiality risk against availability risk, and for a household ledger
  availability is worth more.
- A sealed printed secret is a physical object that can be lost in a move, found
  by a visitor, or forgotten. It needs a known place and a note in the procedure.
- Adding a secret is now a two-step act, and the discipline will slip.
- Rotation is event-driven, so an exposure nobody notices is never rotated away.

**What becomes harder to change later:** nothing technical. The habit is the
artefact here, and habits are what erode — which is why the rehearsal is a task
in a spec rather than a good intention.
