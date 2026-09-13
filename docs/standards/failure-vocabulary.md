# The failure vocabulary

Eleven specs each enumerate their own edge cases, which is right — and between
them they invented a dozen ways to be broken without ever agreeing on the names.
This is the shared list: every failure state the household or an admin can meet,
what it is called, who is told, and what happens next.

Three rules hold for all of them, and they are the reason this document exists:

- **Nothing fails silently.** A state not on this list, reached by the system, is
  a defect.
- **Every failure names its next step.** "Something went wrong" is not a state.
- **A failure has one owner.** A member is never shown infrastructure, and an
  admin is never left guessing which component.

## The member's failures

These are ordinary, expected, and phrased by Meow (`agent-persona.md`): the fault
is his, never theirs.

| Name | When | What the member gets | Where it lives |
|---|---|---|---|
| **Unparsed capture** | No balanced transaction could be produced | The message is kept, and **one** question that would resolve it | `capture`, state unparsed |
| **Model unavailable** | The gateway failed after one retry | The capture is kept; told it will be handled. Never an error code | `capture`, unparsed |
| **Schema violation** | The model answered outside its declared schema | Indistinguishable from unparsed, deliberately | `capture` + the response in the audit log |
| **Cost ceiling reached** | The task's configured spend cap would be exceeded | Asked to type the amount instead | Recorded on the capture |
| **Unknown account named** | "from savings", and there is no such account | One question; no account is created (ADR 0031) | `capture`, unparsed |
| **Not permitted** | A member tries to change a financial fact | No refusal: the affordance is absent, or it becomes a **correction request** | `correction_request` |
| **Stale action** | A button tapped on a record that has since changed | Says so; never re-applies | — |
| **Conversation abandoned** | A setup or a question left unanswered | Stays resumable and visible; never deleted on a timer | `conversation` |
| **Unlinked channel** | Someone messages the bot who is not linked to a member | A neutral reply that reveals nothing; the attempt is logged | Logged; an admin sees the code |

## The admins' failures

Each of these reaches the admins in Telegram, once per condition, and never
repeats without new information (`ergonomics.md`).

| Name | When | What the admins get | Also visible in |
|---|---|---|---|
| **Ambiguous match** | Two candidates for one statement line | The line, flagged. Never a guess | Reconciliation review |
| **Import refused** | Lines do not reconcile to the closing balance | Nothing applied, and the discrepancy | The import's record |
| **Import overridden** | An admin applied it anyway | Recorded as an override, with who | The import's record |
| **Capture with no statement line** | A reconciled period has a record the bank does not | Flagged for review; never deleted | Reconciliation review |
| **Missed commitment** | A due date passed with no matching transaction | The amount and the date it was due | Month view |
| **Budget exceeded** | Spending crossed a budget for the period | Once, for that period. Never to the member who crossed it | Budgets |
| **Projected overdraft** | The forecast dips below zero or a limit | The date and the shortfall | Forecast |
| **Queue ceiling** | Unconfirmed records older than the configured age exceed the threshold | Once. A queue nobody drains is a process failure, not a data state | Home, queue |
| **Integrity mismatch** | A stored file's hash no longer matches | Which file, and that it is in the backup set | — |
| **Heartbeat missing** | A scheduled job did not report success in its window | Which job. Silence is the alarm (ADR 0020) | Uptime Kuma |
| **Drift detected** | A running component differs from its committed configuration | Which component | — |
| **Restore verification failed** | The monthly restore did not produce a usable database | Plainly. The backup is **not** counted as good | — |
| **Offsite unreachable** | The nightly backup reached the local copy only | That the offsite copy is missing | — |
| **Boundary unreachable** | The identity provider is down | Surfaces are closed rather than open; the break-glass path is in the runbook | — |

## The app's states

Not failures of the system, but of the moment — and the specs kept confusing the
first two, which is why they are named:

| Name | What it means | What it must not look like |
|---|---|---|
| **Empty because new** | Nothing has been recorded yet | Must not look like a filter returning nothing |
| **Empty because filtered** | No data in this period or category | Must not look like a missing screen; a zero is shown |
| **Loading** | Figures are on their way | A skeleton in the shape of the content, not a spinner |
| **Slow** | Some figures have arrived | Show what is known; never block on the rest |
| **Unreachable** | The data API cannot be reached | Says so with a next step, and **shows no stale figure as current** |
| **Session expired** | Authentication lapsed while open | Re-authenticate and return to the same screen |
| **Provisional data present** | Model-derived statement lines are included | Visibly distinct from authoritative (ADR 0013) |
| **Unconfirmed share** | Part of a total is unvouched-for | Stated beside the figure, always, even at zero |

## Using it

- A spec's edge-case table **names states from this list** and adds a row here when
  it genuinely needs a new one.
- Each state's user-facing wording lives in the message catalogue (ADR 0017), in
  both languages — never as a literal.
- A review checks the negative paths against this document, because a failure
  nobody implemented looks exactly like a failure that cannot happen.
