---
id: 0034
title: Deployment settings are environment variables; household settings are data; nothing is hard-coded
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
amends: [0010]
---

# ADR 0034 — Deployment settings are environment variables; household settings are data; nothing is hard-coded

## Context

The decisions made so far have accumulated a surprising number of knobs: which
delivery mode Telegram uses, which model serves each task, the spend ceiling per
task, the auto-confirmation quiet period and its amount threshold, the statement
match tolerance, the limit-alert proportion, the forecast horizon, the
belongs-to-a-project threshold, the digest schedule, the household's timezone and
currency.

Every one of them will otherwise end up as a number inside a workflow node or a
SQL function, where it is invisible, undocumented and changeable only by whoever
knows it is there. ADR 0010 already says configuration passes through environment
variables — but applied literally to all of the above it would be wrong in the
other direction: an overdraft limit or a digest preference in `.env` can only be
changed by someone with access to the host, which for a household setting is
absurd.

So the rule needs a line through it, and that line is *who needs to change it*.

## Decision

**Nothing is hard-coded. Everything is either an environment variable or a row in
the database, and which one is decided by who needs to change it.**

### Environment variables — deployment and operations

Anything a **developer or an administrator of the deployment** changes, and which
is meaningless to a household member:

- the Telegram delivery mode and the bot token (ADR 0033);
- model gateway base URL, key, the per-task model ids and the routing table, the
  stub URL used by tests (ADR 0029);
- spend ceilings and the daily cost threshold;
- database and component connection details, the JWT secret, the n8n encryption
  key;
- the public hostname, the ingress mode, backup destination and retention;
- heartbeat URLs and windows;
- technical tolerances that are not per-account: the auto-confirmation quiet
  period, the default match tolerance, the default project-question threshold.

Rules: **every variable appears in `.env.example` by name with no value**; a
missing required variable makes the component fail at startup rather than at
first use; no default is buried in code where the variable is absent.

### Database rows — the household's own settings

Anything a **member or an admin** changes, through the app or by talking to the
agent:

- accounts, their terms and limits, and categories (ADR 0031);
- each member's language, default payment account, and digest preferences;
- budgets, commitments, projects and wishes;
- per-account overrides of the technical defaults above — a match tolerance or an
  alert proportion that differs for one card;
- the household timezone and default currency, collected at setup.

Rules: an admin can change all of it without a deploy; changes are audited
(ADR 0008); a per-account override falls back to the environment default when
absent, and the fallback is visible rather than silent.

### The test that decides

One question: **would a household member ever want this changed, and would asking
a developer be a reasonable answer?** If asking a developer is unreasonable, it is
data. If the setting means nothing to them, it is an environment variable.

A number that is neither — a magic constant in a workflow or a function — is a
defect, and the drift check (ADR 0010) treats an undocumented variable the same
way.

## Alternatives

| Option | Why rejected |
|---|---|
| Everything in environment variables | ADR 0010 read literally. It puts overdraft limits and digest preferences behind host access, which is the wrong person for a household setting, and it forces a restart to change a preference |
| Everything in the database | Tempting for uniformity, and it puts secrets and connection details in the thing they are needed to connect to. Bootstrapping becomes circular |
| A settings UI over a generic key-value table | One screen for every knob, and it invites a household member to change a model id. The split above is what keeps the dangerous knobs away from the people who should not be turning them |
| A configuration file in the repository | Would mean a commit and a deploy to change a threshold, and secrets adjacent to settings |
| Leave the defaults in code and add variables when needed | How magic numbers accumulate. The variable comes first; the code reads it |

## Consequences

**Good:**
- Every knob has one obvious home, and the test for which is a single question.
- The household can change what concerns it without touching a server, and
  cannot change what does not.
- `.env.example` becomes an inventory of the deployment's surface, which is also
  what makes the rebuild claim checkable (ADR 0010).
- Failing at startup on a missing variable turns a class of silent
  misconfiguration into a loud one.

**Bad, and the price we accept:**
- Two places to look when something behaves unexpectedly, and per-account
  overrides mean a value can come from either.
- More plumbing than hard-coding: every threshold needs a variable, a default in
  `.env.example`, and possibly an override column.
- The boundary is a judgement, and some settings sit near it — the digest
  schedule is defensible in either place. It is resolved by the test above rather
  than by argument.

**What becomes harder to change later:** moving a setting across the line once
either side depends on it — a per-account override column, or an operator's
muscle memory. Cheap compared with finding a constant buried in a workflow.
