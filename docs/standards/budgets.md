# Budgets: latency, cost and size

Eleven specs carry their own non-functional requirements, and none of them could
say whether a number was consistent with the others, so we collected the shared
baselines here. A spec refines these numbers instead of reinventing them: it can
be stricter as long as it says so, and it must not be looser without saying why.

## Latency

These budgets cover the paths where a person is waiting, because a machine
waiting costs the household nothing.

| Path | Budget | Why that number |
|---|---|---|
| Text capture to confirmation | 3 s, and 5 s at the 95th | Someone is at a till with a bag in one hand |
| Voice capture to confirmation | 5 s | Same person, more upload |
| Photo capture to confirmation | 10 s, and the reply must arrive whether or not they are still looking | The phone is back in a pocket by then |
| A question in chat to an answer | 3 s | One model call for mapping plus one query |
| App first useful paint, mobile data | 2 s, with something real before everything | A glance that takes longer is not a glance |
| Any keystroke on desktop to visible result | 100 ms | The keyboard model is only fast if it feels instant (ADR 0037) |
| Statement import of one month | 30 s, atomic | Nobody watches it, but nobody should wonder either |
| Forecast read | 1 s | Derived on every read by design, so it has to be cheap |
| Digest generation | background; nobody waits | |

A slow model never blocks a capture: the agent stores the message and answers it
later (vision principle 6). When a path exceeds its budget, record it as a
finding rather than treating it as how the system works.

## Cost

We chose low-code and self-hosting so that running meowhub stays this cheap, and
the table below is what we expect to pay.

| Item | Expected | Notes |
|---|---|---|
| EU host, rented phase | 5-10 EUR / month | Hetzner CX-class; the home phase replaces it with a small relay |
| EU offsite backup storage | 1-4 EUR / month | A Storage Box is the cheap end; growth is the audit log and files |
| Model usage | 2-8 EUR / month | Falls as the merchant registry fills: a known merchant costs nothing (ADR 0004) |
| Apple Developer, if taken | 99 USD / year | Optional; email and password onboards everyone without it (ADR 0032) |
| Total, steady state | under 15 EUR / month | If it is not, something is wrong rather than expensive |

The control on cost is the spend cap and not the estimate above: prepaid credits
and a key limit bound the worst case, and a daily threshold alerts (ADR 0029). If
a month exceeds the model budget, we expect to explain it in one sentence, and
the usual explanation is a statement imported as PDF.

## Size and scale

These numbers are deliberately small, because designing for more would cost us
clarity.

| Dimension | Expected | What it justifies |
|---|---|---|
| Members | 3, up to 6 | No pagination in member views; no bulk user management |
| Accounts | under 20 | A picker, not a search |
| Categories | 20-60, growing slowly | A learned taxonomy with merging (ADR 0031) |
| Transactions | about 2 000 / year | A single PostgreSQL with no partitioning, ever |
| Statement lines | about 1 500 / year | Import in one transaction |
| Files | about 800 / year, a few hundred MB | Content-addressed on a volume (ADR 0019) |
| Database after 10 years | single-digit GB | Logical dumps stay minutes, not hours (ADR 0009) |
| Concurrent app users | 3 | No caching layer, no read replica |

If one of these turns out to be an order of magnitude wrong, revisit first the
decisions that lean on it: derived balances, no pagination, and whole-database
dumps.

## Availability

The household owns uptime (ADR 0002), so an hour down costs nothing, a day is
noticeable, and a week means captures were lost to memory rather than to the
system. Our recovery point is one night (ADR 0009), which means up to a day of
captures might have to be re-entered. Our recovery time is an evening, achievable
by either admin from the written procedure (ADR 0024). We run no redundancy
anywhere - a single host and a single database - and we traded it away
deliberately, because this is a household ledger.

## Heartbeat windows

A heartbeat window is how long a scheduled job can stay silent before Uptime Kuma
alerts (ADR 0020). We start each window generously, because a too-tight window
produces false alarms and false alarms are how alerting dies, and we tighten a
window only once the job's real cadence is settled.

| Job | Window | Why that number |
|---|---|---|
| Drift check | 24 h | Runs daily at 03:00 from the scheduler container (spec 0001 T16); the window is one full cycle, so a single slow or missed run does not itself alarm |
| Nightly backup | 36 h | Meant to run nightly (spec 0001 T14); half again as long as its own cadence so one slow night is not a false alarm, tightened once it actually runs on a schedule |
| Digest tick | 2 h | The tick runs hourly (spec 0004 T11) and pushes only when it answered; twice its own cadence, so one missed hour is not a false alarm but a stopped digest is noticed the same morning |
| Monthly restore verification | 24 days | Meant to run monthly (spec 0001 T15); Kuma's own interval cap (2,073,600 s) is the actual ceiling here, not a chosen number, and it is the closest this window gets to "monthly, generous" |
