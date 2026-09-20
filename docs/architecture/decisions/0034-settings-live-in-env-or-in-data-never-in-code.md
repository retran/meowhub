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

# ADR 0034 - Deployment settings are environment variables; household settings are data; nothing is hard-coded

## Context

The decisions so far have accumulated a surprising number of knobs: which
delivery mode Telegram uses, which model serves each task, the spend ceiling per
task, the auto-confirmation quiet period and its amount threshold, the statement
match tolerance, the limit-alert proportion, the forecast horizon, the
belongs-to-a-project threshold, the digest schedule, the household's timezone and
currency.

Unless we decide otherwise, each of those becomes a number inside a workflow node
or a SQL function, where nobody sees it, nothing documents it, and only whoever
remembers it's there can change it. ADR 0010 already says configuration passes
through environment variables, and applied literally to the whole list it fails
in the other direction, because an overdraft limit or a digest preference in
`.env` can be changed only by someone with access to the host, which is the wrong
person for a household setting.

The rule therefore needs a line drawn through it, and the line is who needs to
change the setting.

## Decision

We hard-code nothing. Every setting is either an environment variable or a row in
the database, and who needs to change it decides which.

### Environment variables - deployment and operations

A setting becomes an environment variable when a developer or an administrator of
the deployment changes it and it means nothing to a household member:

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

Three rules go with them. Every variable appears in `.env.example` by name with
no value. A component that's missing a required variable fails at startup instead
of at first use. And no default hides in code for the case where the variable is
absent.

### Database rows - the household's own settings

A setting becomes a database row when a member or an admin changes it, through
the app or by talking to the agent:

- accounts, their terms and limits, and categories (ADR 0031);
- each member's language, default payment account, and digest preferences;
- budgets, commitments, projects and wishes;
- per-account overrides of the technical defaults above - a match tolerance or an
  alert proportion that differs for one card;
- the household timezone and default currency, collected at setup.

Three rules go with these as well. An admin changes any of them without a deploy.
We audit the changes like anything else (ADR 0008). And a per-account override
falls back to the environment default when it's absent, visibly rather than
silently.

### The test that decides

One question settles which side a setting belongs on: would a household member
ever want it changed, and would asking a developer be a reasonable answer? If
asking a developer is unreasonable, the setting is data; if the setting means
nothing to a member, it's an environment variable.

A number that's neither - a magic constant in a workflow or a function - is a
defect, and the drift check (ADR 0010) treats an undocumented variable as one
too.

## Alternatives

| Option | Why rejected |
|---|---|
| Everything in environment variables | ADR 0010 read literally. It puts overdraft limits and digest preferences behind host access, which is the wrong person for a household setting, and it forces a restart to change a preference |
| Everything in the database | Tempting for uniformity, and it puts secrets and connection details in the thing they are needed to connect to. Bootstrapping becomes circular |
| A settings UI over a generic key-value table | One screen for every knob, and it invites a household member to change a model id. The split above is what keeps the dangerous knobs away from the people who should not be turning them |
| A configuration file in the repository | Would mean a commit and a deploy to change a threshold, and secrets adjacent to settings |
| Leave the defaults in code and add variables when needed | How magic numbers accumulate. The variable comes first; the code reads it |

## Consequences

Good:
- Every knob has one obvious home, and one question decides which.
- The household can change what concerns it without touching a server, and can't
  change what doesn't.
- `.env.example` becomes an inventory of the deployment's surface, which is also
  what makes the rebuild claim checkable (ADR 0010).
- Failing at startup on a missing variable turns a class of silent
  misconfiguration into a loud one.

Bad, and the price we accept:
- Anyone debugging unexpected behaviour has two places to look, and per-account
  overrides mean a value can come from either.
- We write more plumbing than hard-coding needs: every threshold takes a
  variable, an entry in `.env.example`, and sometimes an override column.
- The boundary is a judgement, and some settings sit near it - the digest
  schedule is defensible on either side. The test above resolves those, so nobody
  has to argue them.

What becomes harder to change later is moving a setting across the line once
either side depends on it, whether that's a per-account override column or an
operator's muscle memory. That still costs less than finding a constant buried in
a workflow.
