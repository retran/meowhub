# Budgets: latency, cost and size

Eleven specs carry their own non-functional requirements, and none of them could
say whether a number was consistent with the others. These are the shared
baselines they refine rather than reinvent: a spec may be stricter and must say
so, and may not be looser without saying why.

## Latency

What matters is where a person is waiting, not where a machine is.

| Path | Budget | Why that number |
|---|---|---|
| Text capture → confirmation | **3 s**, and 5 s at the 95th | Someone is at a till with a bag in one hand |
| Voice capture → confirmation | **5 s** | Same person, more upload |
| Photo capture → confirmation | **10 s**, and the reply must arrive whether or not they are still looking | The phone is back in a pocket by then |
| A question in chat → an answer | **3 s** | One model call for mapping plus one query |
| App first useful paint, mobile data | **2 s**, with something real before everything | A glance that takes longer is not a glance |
| Any keystroke on desktop → visible result | **100 ms** | The keyboard model is only fast if it feels instant (ADR 0037) |
| Statement import of one month | **30 s**, atomic | Nobody watches it, but nobody should wonder either |
| Forecast read | **1 s** | Derived on every read by design, so it has to be cheap |
| Digest generation | background; nobody waits | |

**A slow model never blocks a capture**: the message is stored and answered later
(vision principle 6). Exceeding a budget is a finding, not a feature.

## Cost

The whole point of the low-code, self-hosted choice is that this stays small.

| Item | Expected | Notes |
|---|---|---|
| EU host, rented phase | **€5–10 / month** | Hetzner CX-class; the home phase replaces it with a small relay |
| EU offsite backup storage | **€1–4 / month** | A Storage Box is the cheap end; growth is the audit log and files |
| Model usage | **€2–8 / month** | Falls as the merchant registry fills: a known merchant costs nothing (ADR 0004) |
| Apple Developer, if taken | **99 USD / year** | Optional; email and password onboards everyone without it (ADR 0032) |
| **Total, steady state** | **under €15 / month** | If it is not, something is wrong rather than expensive |

**The spend cap is the control, not the estimate**: prepaid credits and a key
limit bound the worst case, and a daily threshold alerts (ADR 0029). A month that
exceeds the model budget should be explainable in one sentence — usually a
statement imported as PDF.

## Size and scale

Deliberately small numbers, because designing for more would cost clarity.

| Dimension | Expected | What it justifies |
|---|---|---|
| Members | 3, up to 6 | No pagination in member views; no bulk user management |
| Accounts | under 20 | A picker, not a search |
| Categories | 20–60, growing slowly | A learned taxonomy with merging (ADR 0031) |
| Transactions | ~2 000 / year | A single PostgreSQL with no partitioning, ever |
| Statement lines | ~1 500 / year | Import in one transaction |
| Files | ~800 / year, a few hundred MB | Content-addressed on a volume (ADR 0019) |
| Database after 10 years | single-digit GB | Logical dumps stay minutes, not hours (ADR 0009) |
| Concurrent app users | 3 | No caching layer, no read replica |

If any of these turns out an order of magnitude wrong, the decisions that lean on
them — derived balances, no pagination, whole-database dumps — are the ones to
revisit first.

## Availability

- **The household owns uptime** (ADR 0002). An hour down costs nothing; a day is
  noticeable; a week means captures were lost to memory rather than to the system.
- **Recovery point: one night** (ADR 0009). Up to a day of captures may need
  re-entering.
- **Recovery time: an evening**, by either admin, from the written procedure
  (ADR 0024).
- **No redundancy anywhere**, single host, single database, and that is a
  deliberate trade for a household ledger.

## Heartbeat windows

How long a scheduled job's silence is tolerated before Uptime Kuma alerts
(ADR 0020). Deliberately generous to start — a too-tight window produces false
alarms, which is how alerting dies — and tightened only once the job's real
cadence is settled.

| Job | Window | Why that number |
|---|---|---|
| Drift check | **24 h** | Runs daily at 03:00 from the scheduler container (spec 0001 T16); the window is one full cycle, so a single slow or missed run does not itself alarm |
| Nightly backup | **36 h** | Meant to run nightly (spec 0001 T14); half again as long as its own cadence so one slow night is not a false alarm, tightened once it actually runs on a schedule |
| Monthly restore verification | **24 days** | Meant to run monthly (spec 0001 T15); Kuma's own interval cap (2,073,600 s) is the actual ceiling here, not a chosen number — the closest this window gets to "monthly, generous" |
