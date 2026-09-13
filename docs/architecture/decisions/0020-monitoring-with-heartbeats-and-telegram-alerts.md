---
id: 0020
title: Monitoring is heartbeats and health checks in Uptime Kuma, alerting to Telegram
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0020 — Monitoring is heartbeats and health checks in Uptime Kuma, alerting to Telegram

## Context

Several ADRs already promise that failures reach the admins in Telegram: a failed
backup or restore verification (ADR 0009), configuration drift (ADR 0010), a file
integrity mismatch (ADR 0019). All of those are alerts sent *by a job that ran*.

Nothing covers the opposite and more likely failure: **a job that did not run, and
a service that is simply dead.** A bot that stopped responding is discovered by a
member's message going unanswered, which may be days. A nightly backup whose
container failed to start sends nothing at all — and silence is
indistinguishable from success. For a system whose entire value is an unbroken
financial record, silence is the dangerous state.

nexus answered this with a full LGTM stack — Alloy, Tempo, Mimir, Grafana. That is
the correct answer for a platform and absurd for four containers serving three
people.

## Decision

**Uptime Kuma**, one container, as the single place that knows whether things are
alive — with Telegram as the notification channel, so every alert in this system
arrives in the same place.

Two kinds of monitor, and the second is the one that matters:

- **Health checks** — HTTP probes of each service's health endpoint: the bot's
  webhook path, PostgREST, the app, the identity provider, and PostgreSQL through
  a trivial query endpoint. Answers "is it up".
- **Heartbeats (dead man's switches)** — every scheduled job pushes to a Kuma URL
  **on success**: the nightly backup, the monthly restore verification, drift
  detection, the file integrity check, the statement import if it becomes
  scheduled, and each digest. If the push does not arrive inside its window,
  Kuma alerts. This inverts the failure mode: **silence becomes an alarm instead
  of a false comfort.**

Other rules:

- **Alert once, to Telegram, to the owner** — not to the household. A member does
  not need to know PostgREST restarted.
- **Kuma is a container in the same Compose file** (ADR 0002) and moves home with
  everything else. Its own configuration is part of the backup set.
- **Kuma watching itself is not a thing**, so the one gap is accepted knowingly:
  if Kuma dies, alerts stop silently. Mitigation is a single external check —
  Kuma's own push to a free third-party dead man's switch, or simply the
  household noticing the absence of the weekly digest, which is itself a
  heartbeat visible to people.
- **No metrics, traces or log aggregation.** Container logs on the host are
  enough at this size; the logs that matter for the product — model exchanges,
  imports, changes — are in PostgreSQL already (ADR 0008). This is a deliberate
  refusal, revisited only if something is actually hard to diagnose.

## Alternatives

| Option | Why rejected |
|---|---|
| The LGTM stack, as in nexus | Five or six containers and a memory budget, to observe four services. The very cost of ownership meowhub exists to avoid |
| Healthchecks.io or another hosted dead man's switch | Genuinely simpler for heartbeats and no container to run, but it puts the monitoring of a private system outside it and breaks when the home connection is the thing being monitored. Kept as the one external check that watches Kuma itself |
| Docker restart policies and nothing else | Restarts a crashed container and says nothing about a job that never ran or a container stuck in a healthy-looking loop |
| Prometheus plus Alertmanager | The right tool for metrics-based alerting on a system that has metrics worth alerting on. This one does not, yet |
| Alerts by email | The household reads Telegram; email is where alerts go to be ignored |
| Only the alerts jobs already send | Covers every failure except the ones where nothing runs, which are the failures that stay hidden longest |

## Consequences

**Good:**
- A job that stops running is noticed within its own window, not eventually.
- One channel for every alert in the system, which is the only way alerts keep
  being read.
- One container, trivial to operate, and it moves home with the rest.

**Bad, and the price we accept:**
- Kuma is a single point of unobserved failure, mitigated by one external check
  rather than solved.
- Heartbeat windows need tuning, and a too-tight window produces false alarms —
  which is how alerting dies.
- Every scheduled job now has a second responsibility: to say it succeeded. A job
  that pushes its heartbeat before finishing its work would report success
  falsely, so the push belongs at the end, after verification.

**What becomes harder to change later:** nothing. Monitors are configuration, and
if this system ever grows into needing metrics, heartbeats remain valid alongside
them.
