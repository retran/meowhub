---
id: 0020
title: Monitoring is heartbeats and health checks in Uptime Kuma, alerting to Telegram
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0020 - Monitoring is heartbeats and health checks in Uptime Kuma, alerting to Telegram

## Context

Several ADRs already promise that failures reach the admins in Telegram: a
failed backup or restore verification (ADR 0009), configuration drift
(ADR 0010), a file integrity mismatch (ADR 0019). Every one of those alerts is
sent by a job that ran.

Nothing covers the opposite and more likely failure, where a job doesn't run at
all or a service is dead. If the bot stops responding, the household finds out
when a member's message goes unanswered, which can take days. A nightly backup
whose container failed to start sends nothing, and nothing looks exactly like
success. For a system whose whole value is an unbroken financial record, that
silence is the dangerous state, because it hides the failure for as long as
nobody happens to look.

nexus answered this with a full LGTM stack - Alloy, Tempo, Mimir, Grafana. That
is the right answer for a platform and an absurd one for four containers serving
three people.

## Decision

We run **Uptime Kuma** in one container as the single place that knows whether
things are alive, and we send its notifications to Telegram so that every alert
in this system arrives where the others do.

There are two kinds of monitor, and the second is the one that matters:

- Health checks are HTTP probes of each service's health endpoint: the bot's
  webhook path, PostgREST, the app, the identity provider, and PostgreSQL
  through a trivial query endpoint. They answer whether a service is up.
- Heartbeats, also called dead man's switches, are a push to a Kuma URL that
  every scheduled job sends on success: the nightly backup, the monthly restore
  verification, drift detection, the file integrity check, the statement import
  if it becomes scheduled, and each digest. Kuma alerts when the push doesn't
  arrive inside its window, so a job that stops running raises an alarm instead
  of passing for a quiet night.

Other rules:

- Kuma alerts once, to Telegram, to the owner and not to the household, because
  a member doesn't need to know that PostgREST restarted.
- Kuma is a container in the same Compose file (ADR 0002) and moves home with
  everything else, and its own configuration is part of the backup set.
- Kuma can't watch itself, so we accept one gap knowingly: if Kuma dies, alerts
  stop and nothing says so. We reduce it with a single external check, either
  Kuma's own push to a free third-party dead man's switch or the household
  noticing that the weekly digest didn't arrive, which is a heartbeat people can
  see.
- We collect no metrics, traces or aggregated logs. Container logs on the host
  are enough at this size, and the logs that matter for the product - model
  exchanges, imports, changes - are already in PostgreSQL (ADR 0008). We refuse
  this deliberately and will revisit it only when something turns out to be hard
  to diagnose.

## Alternatives

| Option | Why rejected |
|---|---|
| The LGTM stack, as in nexus | Five or six containers and a memory budget, to observe four services. That cost of ownership is what meowhub exists to avoid |
| Healthchecks.io or another hosted dead man's switch | Genuinely simpler for heartbeats, with no container to run, but it puts the monitoring of a private system outside it and breaks when the home connection is the thing being monitored. We keep it as the one external check that watches Kuma itself |
| Docker restart policies and nothing else | Restarts a crashed container and says nothing about a job that never ran or a container stuck in a healthy-looking loop |
| Prometheus plus Alertmanager | The right tool for metrics-based alerting on a system that has metrics worth alerting on, and this one doesn't yet |
| Alerts by email | The household reads Telegram, and email is where alerts go to be ignored |
| Only the alerts jobs already send | Covers every failure except the ones where nothing runs, which are the failures that stay hidden longest |

## Consequences

**Good:**
- A job that stops running is noticed inside its own window, instead of
  eventually.
- Every alert in the system arrives in one channel, which is what keeps people
  reading alerts.
- One container, which is easy to operate and moves home with the rest.

**Bad, and the price we accept:**
- Kuma is a single point of failure that nothing observes, and one external
  check reduces that rather than solving it.
- Heartbeat windows need tuning, because a window that is too tight produces
  false alarms, and false alarms are how alerting dies.
- Every scheduled job now has a second job, to say that it succeeded. A job that
  pushes its heartbeat before finishing its work would report success falsely,
  so the push belongs at the end, after the job has verified its own result.

**What becomes harder to change later:** nothing. Monitors are configuration,
and if this system ever grows to need metrics, heartbeats still work alongside
them.
