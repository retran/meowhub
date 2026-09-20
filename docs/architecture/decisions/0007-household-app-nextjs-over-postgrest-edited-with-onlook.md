---
id: 0007
title: The household app is a small Next.js app over PostgREST, edited visually with Onlook
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0007 - The household app is a small Next.js app over PostgREST, edited visually with Onlook

## Context

Chat is how expenses go *in*, and it is a poor way to look at trends, because a
chart in a chat bubble is a worse chart. A household member asked for this, not
the owner: she wants to open something on a phone and see where the money is
going, so the app has to be pleasant on an iPhone for someone with no interest
in the plumbing.

Four constraints decide what such an application can be here.

Low-code here means little code, not building by mouse (vision principle 5). A
handful of screens over an API that already exists counts as little code, and a
bespoke platform does not.

An agent does the work, spec-driven, so whatever holds the screens has to be
something an agent can build, review, test and rebuild, and ADR 0010 requires us
to restore it from this repository. That rules out any builder whose app
definition lives only inside its own UI, because those screens can only ever be
clicked together by hand.

Appearance is the admins' call, and changing it must not require writing prose.
If layout belongs to the agent, every visual change turns into a description and
a diff, and that is the one thing a visual builder genuinely does better, so we
have to answer it instead of arguing it away.

Almost nothing needs to be built. All aggregation already has to live in SQL
views (ADRs 0004, 0011), and PostgREST (ADR 0014) turns those views into an API
for free, which leaves layout and fetching.

## Decision

The household app is **a small Next.js app with Tailwind CSS** that reads the
ledger from PostgREST (ADR 0014), served as a static build behind the same
identity provider as everything else (ADR 0032) and installable to the iPhone
home screen. It has no backend of its own, no builder and no native app.

We adopt [Onlook](https://github.com/onlook-dev/onlook) as the visual editing
tool for it: Apache-2.0, run locally. Onlook opens this repository's app, runs
its dev server and renders it on a canvas, and each element carries an `oid`, so
it finds a visual change in the matching JSX, patches the source file and
hot-reloads, keeping formatting and component structure intact. Right-clicking
an element opens its exact place in the code.

That settles who does what, which is the point of the choice:

- The agent builds and maintains the app: SQL views, PostgREST configuration and
  row-level security, screens, data fetching and tests.
- The owner adjusts how it looks, by mouse, against the same codebase, instead
  of describing a change and waiting for a diff.
- Everything from either hand lands in git as reviewable TypeScript.

We take Onlook's requirements as constraints on the app rather than working
around them: Next.js and Tailwind, with styling in Tailwind classes instead of
hidden behind a component library, because that declarative shape is what makes
visual editing work. It is a real limit on how we write the app, and it is cheap
to honour at this size.

### Scope discipline

- The app reads first: trends, category and merchant breakdowns, balances per
  account, a per-member view, and month-over-month comparison.
- The only writes are corrections: amount, category, merchant and payment
  account on an existing transaction, merchant merges, and confirming or
  overriding a reconciliation. Capture stays in the chat.
- Every screen answers a question somebody actually asked, and we build no
  speculative screens.
- The app computes no totals. Every number comes from a view, so the app and the
  bot's digests cannot disagree and the app stays replaceable.
- Provenance is visible, so a provisional, model-derived statement line looks
  different from an authoritative one (ADR 0013).

## Alternatives

| Option | Why rejected |
|---|---|
| Budibase | Excellent free styling, with custom CSS on every component, and batteries included: auth, hosting, CRUD. But it gives an agent no way to author an app, only an open proposal, so every screen and every revision costs the owner an evening in the builder. White-labelling and app environment variables are paid, and its JSON export is verbose enough that reviewing it is theoretical |
| ToolJet | Ships an MCP server, so an agent can author its apps directly, and exports JSON with an import API, which makes it the best process fit among the builders. We rejected it because the owner does not like the product, and that is enough for a surface his household uses daily |
| Appsmith | Free native git version control is the strongest config-as-code story of the builders, but it has no application-level custom CSS at all, it is the heaviest to run, and its mobile layouts are the weakest |
| Windmill apps | Would fold the orchestrator and the UI into one tool we are already considering, and it is genuinely code-first. Internal-tool aesthetics, unproven mobile polish, and it would couple two roles we would rather keep separate |
| Evidence.dev | The purest "little code" answer: SQL plus markdown, output that reads like a designed report, everything in git. We rejected it on maintenance risk, because its last commit was February 2026 and the project shows signs of winding down, so we would regret the dependency |
| Metabase | Actively maintained and decent on mobile, but it presents as a BI product instead of the household's own app |
| Grafana | Dashboards provisioned from files, and an ops console on a phone |
| A hand-written app with no visual editing | This decision minus Onlook. We rejected it because it leaves every appearance change as a conversation with the agent, which is the friction a builder was meant to remove |

## Consequences

We gain five things:

- Little code, and all of it reviewable, because the app is a few screens of
  fetch and layout over views that had to exist anyway.
- Both hands work on one artefact, the agent through the code and the owner
  through Onlook, with git as the single history.
- The config-as-code weak spot disappears, because no exported bundle has to be
  reconciled: the app *is* the repository (ADR 0010).
- The best mobile result available to us, since no builder's renderer constrains
  it.
- No paid tier anywhere in this component, and no vendor that can gate us.

We accept four costs in return:

- **This is the project's first real application code**, and the one component a
  container upgrade cannot improve. It needs tests, dependency maintenance and
  the occasional framework migration, forever.
- Onlook is in early access, and it holds the app to Next.js plus Tailwind with
  unabstracted styling. If it stalls or breaks, the app survives, because it is
  ordinary code, but the visual editing does not, and appearance changes become
  a conversation again.
- Budibase's batteries are now ours to supply: authentication comes from the
  proxy (ADR 0032), authorization from row-level security (ADR 0014), and
  hosting is a static build.
- The app adds a second writer to the ledger through corrections, which is why
  database triggers enforce the audit log (ADR 0008).

The framework choice gets mildly harder to change later, because Onlook's
requirements bake in Next.js and Tailwind instead of us choosing them on their
own merits. Keeping the app thin and every number in a view is what keeps even
that cheap to undo.
