# Threat model

PostgreSQL row-level security carries the authorisation in this system
(ADR 0014), and ADR 0015 makes its policies the most-tested thing in the project.
Tests written without a threat model are mechanical, because they assert whatever
the policy happens to say, so this document says what the tests are *for*.

We kept it short on purpose. A three-person household is not an enterprise, and a
threat model that inventories imaginary adversaries is a document nobody reads.

## What is being protected

Five assets are worth defending, and the worst case differs for each one.

| Asset | Why it matters | Worst case |
|---|---|---|
| The ledger | A decade of the household's financial history; irreplaceable | Total loss, or silent corruption nobody notices for months |
| Statement and receipt files | The household's complete financial picture, and photographs of daily life | Disclosure |
| The audit log | The only way to explain or reverse anything | Rewriting, which makes a mistake and a cover-up identical |
| Secrets | The restic password gates every backup copy | Without it, the backups are ciphertext forever |
| Availability of capture | An unusable bot means abandonment | The books stop being kept |

## Who we defend against

We defend against five adversaries, listed here in order of how likely each one
is to cause damage.

1. Accident by a household member. This is by far the most probable cause of
   damage - a stray tap, a bulk reconciliation approved unread, or a deletion
   meant for something else - so it is the primary adversary, and most of the
   design answers it: admin-only edits (ADR 0016), an append-only audit log
   (ADR 0008), reversible imports (ADR 0013), and a confirmation state
   (ADR 0023).
2. An opportunistic stranger on the internet. Anyone who finds the bot can reach
   it, and the web surfaces have a public hostname, so the allow-list (ADR 0030),
   the authentication boundary (ADR 0032), and default-deny policies answer this
   one.
3. A compromised member device, such as a phone left unlocked or lost, whose
   passkey and Telegram session are then valid. Revocation answers it, and we
   accept part of the risk, because a household member's device sits inside the
   trust boundary.
4. A dependency or supply-chain failure, such as a malicious package in the app
   or a compromised container image. Our answer here is weak: pinned versions,
   few dependencies, and a database that enforces its own rules whatever a client
   does.
5. Our own bugs - a missing policy on a new table, a view exposing more than we
   intended, or a prompt writing something unbalanced - answered by default-deny,
   the double-entry invariant in the database, and impersonation tests.

Six threats are explicitly out of scope, because defending against them would
cost more than the household can justify or would contradict how it works.

- A targeted attacker with resources aimed at this household specifically.
- A malicious admin. We trust both admins absolutely and the system gives them
  the keys by design, because defending the books from the people who own them
  makes no sense.
- Physical seizure of the home server.
- The hosting provider or Cloudflare reading traffic in transit, which we
  accepted in ADR 0002 and which is why the authentication boundary sits at the
  application and not at the network.
- OpenRouter seeing capture text and receipt images, accepted in ADR 0029, with
  sending as little data as possible as the mitigation.
- Regulatory or legal data-subject obligations, because this is a private
  household system (ADR 0026).

## The properties the tests must prove

Each assertion below maps to a test rather than to a paragraph, and together they
are what the row-level security suite exists to prove.

1. A member who is not an admin cannot change or delete a recorded transaction
   through any path: the bot, the app, the data API, or a direct database
   session.
2. No unauthenticated request reads anything, for every exposed view, enumerated
   rather than sampled.
3. A new table or view is unreachable until a policy grants access, because
   default deny makes a forgotten policy fail closed instead of open.
4. No client can write an unbalanced transaction, and none can insert a raw
   posting through the data API.
5. No application role can modify or delete the audit log.
6. The boundary rejects a token with a tampered claim, a wrong audience, or an
   expired lifetime.
7. A deactivated member reaches nothing, and existing sessions don't survive
   deactivation.
8. An import can be reversed as a unit, and the reversal is itself audited.

## Accepted risks, stated plainly

Each risk below is a decision we made and not an oversight.

- Two custodians per secret double the disclosure surface, and we accepted that
  to reduce the far greater risk of losing the secret permanently (ADR 0024).
- A member's device sits inside the trust boundary, so a lost, unlocked phone
  exposes the household's books until someone revokes it.
- Capture text and receipt images leave the household twice: to the model gateway
  (ADR 0029) and through Telegram, whose bot conversations aren't end-to-end
  encrypted (ADR 0027). Telegram also sees who captures and when. These are the
  only two exceptions to self-hosting, and both sit in the capture path, away
  from the ledger.
- A tunnel provider can see traffic (ADR 0002).
- Unconfirmed, model-derived records count in the books (ADR 0023), so a wrong
  number is visible instead of withheld, because a lagging ledger costs the
  household more.
- Statement files accumulate indefinitely (ADR 0019), so the store of sensitive
  documents grows and the cost of a breach grows with it.

## Review

We revisit this document when the trust boundary changes: a new member, a new
surface, a new external service, or the move to the home server. We don't revisit
it on a calendar.
