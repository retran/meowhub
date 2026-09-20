# The failure vocabulary

Eleven specs each enumerate their own edge cases, which is right, but between them
they invented a dozen ways to be broken without ever agreeing on the names. This
document is the shared list: every failure state the household or an admin can
meet, what we call it, who is told, and what happens next.

We wrote it down because three rules have to hold across all of those states.
Nothing fails silently, so when the system reaches a state that isn't on this
list, that's a defect. Every failure names its next step, which means "something
went wrong" isn't a state. And every failure has one owner: a member is never
shown infrastructure, and an admin is never left guessing which component broke.

## The member's failures

These failures are ordinary and expected, and Meow phrases them
(`agent-persona.md`) so that the fault is always his and never the member's.

| Name | When | What the member gets | Where it lives |
|---|---|---|---|
| Unparsed capture | No balanced transaction could be produced | The whole exchange is kept, and a question that would resolve it, then a further one if an answer still leaves a gap, and never the same question twice | `capture`, state unparsed |
| Model unavailable | The gateway failed after one retry | The capture is kept, and he is told it will be handled. Never an error code | `capture`, unparsed |
| Schema violation | The model answered outside its declared schema | Deliberately indistinguishable from unparsed | `capture` + the response in the audit log |
| Cost ceiling reached | The task's configured spend cap would be exceeded | Asked to type the amount instead | Recorded on the capture |
| Unknown account named | "from savings", and there is no such account | One question, and no account is created (ADR 0031) | `capture`, unparsed |
| Not permitted | A member tries to change a financial fact | No refusal: the control is absent, or it becomes a correction request | `correction_request` |
| Stale action | A button tapped on a record that has since changed | Says so, and never re-applies | - |
| Conversation abandoned | A setup or a question left unanswered | Stays resumable and visible, and is never deleted on a timer | `conversation` |
| Unlinked channel | Someone messages the bot who is not linked to a member | A neutral reply that reveals nothing, and the attempt is logged | Logged; an admin sees the code |

## The admins' failures

Each of these reaches the admins in Telegram, once per condition, and never
repeats without new information (`ergonomics.md`).

| Name | When | What the admins get | Also visible in |
|---|---|---|---|
| Ambiguous match | Two candidates for one statement line | The line, flagged. Never a guess | Reconciliation review |
| Import refused | Lines do not reconcile to the closing balance | Nothing applied, and the discrepancy | The import's record |
| Import overridden | An admin applied it anyway | Recorded as an override, with who | The import's record |
| Capture with no statement line | A reconciled period has a record the bank does not | Flagged for review, and never deleted | Reconciliation review |
| Missed commitment | A due date passed with no matching transaction | The amount and the date it was due | Month view |
| Budget exceeded | Spending crossed a budget for the period | Once, for that period. Never to the member who crossed it | Budgets |
| Projected overdraft | The forecast dips below zero or a limit | The date and the shortfall | Forecast |
| Queue ceiling | Unconfirmed records older than the configured age exceed the threshold | Once, because a queue nobody drains is a failure of the process and not a state of the data | Home, queue |
| Integrity mismatch | A stored file's hash no longer matches | Which file, and that it is in the backup set | - |
| Heartbeat missing | A scheduled job did not report success in its window | Which job. Uptime Kuma alerts because the job's push did not arrive (ADR 0020) | Uptime Kuma |
| Drift detected | A running component differs from its committed configuration | Which component | - |
| Restore verification failed | The monthly restore did not produce a usable database | Plainly, and we do not count that backup as good | - |
| Offsite unreachable | The nightly backup reached the local copy only | That the offsite copy is missing | - |
| Boundary unreachable | The identity provider is down | Closed surfaces rather than open ones, and the break-glass path is in the runbook | - |

## The app's states

These states are failures of the moment and not of the system. We name them
because the specs kept confusing the first two.

| Name | What it means | What it must not look like |
|---|---|---|
| Empty because new | Nothing has been recorded yet | Must not look like a filter returning nothing |
| Empty because filtered | No data in this period or category | Must not look like a missing screen; a zero is shown |
| Loading | Figures are on their way | A skeleton in the shape of the content, not a spinner |
| Slow | Some figures have arrived | Show what is known, and never block on the rest |
| Unreachable | The data API cannot be reached | Says so with a next step, and shows no stale figure as current |
| Session expired | Authentication lapsed while open | Re-authenticate and return to the same screen |
| Provisional data present | Model-derived statement lines are included | Visibly distinct from authoritative (ADR 0013) |
| Unconfirmed share | Part of a total is unvouched-for | Stated beside the figure, always, even at zero |

## Using it

Use this vocabulary in three places as you write and review a slice.

- A spec's edge-case table names states from this list, and adds a row here only
  when the slice genuinely needs a new one.
- Each state's user-facing wording lives in the message catalogue (ADR 0017), in
  both languages, and never as a literal in a workflow.
- A review checks the negative paths against this document, because a failure
  nobody implemented looks exactly like a failure that cannot happen.
