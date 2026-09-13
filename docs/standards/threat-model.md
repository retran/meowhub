# Threat model

Authorisation in this system is row-level security in PostgreSQL (ADR 0014), and
ADR 0015 makes its policies the most-tested thing in the project. Tests without a
threat model are mechanical: they assert whatever the policy happens to say. This
document says what the tests are *for*.

It is deliberately short. A three-person household is not an enterprise, and a
threat model that inventories imaginary adversaries is a document nobody reads.

## What is being protected

| Asset | Why it matters | Worst case |
|---|---|---|
| The ledger | A decade of the household's financial history; irreplaceable | Total loss, or silent corruption nobody notices for months |
| Statement and receipt files | The household's complete financial picture, and photographs of daily life | Disclosure |
| The audit log | The only way to explain or reverse anything | Rewriting, which makes a mistake and a cover-up identical |
| Secrets | The restic password gates every backup copy | Without it, the backups are ciphertext forever |
| Availability of capture | An unusable bot means abandonment | The books stop being kept |

## Who we defend against

**In scope, in order of likelihood:**

1. **Accident by a household member.** By far the most probable cause of damage:
   a stray tap, a bulk reconciliation approved unread, a deletion meant for
   something else. This is the primary adversary, and most of the design answers
   it — admin-only edits (ADR 0016), an append-only audit log (ADR 0008),
   reversible imports (ADR 0013), a confirmation state (ADR 0023).
2. **An opportunistic stranger on the internet.** The bot is reachable by anyone
   who finds it, and the web surfaces have a public hostname. Answered by the
   allow-list (ADR 0030), the authentication boundary (ADR 0032) and default-deny
   policies.
3. **A compromised member device.** A phone left unlocked or lost. Its passkey and
   its Telegram session are then valid. Answered by revocation, and accepted
   partially: a household member's device is inside the trust boundary.
4. **A dependency or supply-chain failure.** A malicious package in the app, or a
   compromised container image. Answered weakly: pinned versions, few
   dependencies, and the fact that the database enforces its own rules regardless
   of what a client does.
5. **Our own bugs.** A missing policy on a new table, a view exposing more than
   intended, a prompt writing something unbalanced. Answered by default-deny, the
   double-entry invariant in the database, and impersonation tests.

**Explicitly out of scope:**

- A targeted attacker with resources aimed at this household specifically.
- A malicious admin. Both admins are trusted absolutely; the system gives them
  the keys by design, and defending the books from the people who own them is
  incoherent.
- Physical seizure of the home server.
- The hosting provider or Cloudflare reading traffic in transit — accepted in
  ADR 0002, and the reason the authentication boundary is at the application
  rather than the network.
- OpenRouter seeing capture text and receipt images — accepted in ADR 0029, with
  data minimisation as the mitigation.
- Regulatory or legal data-subject obligations. This is a private household
  system (ADR 0026).

## The properties the tests must prove

These are the assertions that matter, and each maps to a test rather than to a
paragraph:

1. **A member who is not an admin cannot change or delete a recorded
   transaction**, through any path — the bot, the app, the data API, or a direct
   database session.
2. **No unauthenticated request reads anything**, for every exposed view,
   enumerated rather than sampled.
3. **A new table or view is unreachable until a policy grants it.** Default deny,
   so a forgotten policy fails closed rather than open.
4. **No client can write an unbalanced transaction**, and none can insert a raw
   posting through the data API.
5. **The audit log cannot be modified or deleted** by any application role.
6. **A token with a tampered claim, a wrong audience, or an expired lifetime is
   rejected.**
7. **A deactivated member reaches nothing**, and existing sessions do not survive
   deactivation.
8. **An import can be reversed as a unit**, and the reversal is itself audited.

## Accepted risks, stated plainly

Each of these is a decision, not an oversight:

- **Two custodians per secret doubles the disclosure surface** to reduce the far
  greater risk of permanent loss (ADR 0024).
- **A member's device is inside the trust boundary.** A lost, unlocked phone
  exposes the household's books until it is revoked.
- **Capture text and receipt images leave the household twice**: to the model
  gateway (ADR 0029) and through Telegram, whose bot conversations are not
  end-to-end encrypted (ADR 0027). Telegram also sees who captures and when.
  These are the only two exceptions to self-hosting, and both sit in the capture
  path rather than near the ledger.
- **A tunnel provider can see traffic** (ADR 0002).
- **Unconfirmed, model-derived records count in the books** (ADR 0023) — wrong
  numbers are visible rather than withheld, because a lagging ledger is worse.
- **Statement files accumulate indefinitely** (ADR 0019), so the store of
  sensitive documents grows and the cost of a breach grows with it.

## Review

This document is revisited when the trust boundary changes: a new member, a new
surface, a new external service, or the move to the home server. Not on a
calendar.
