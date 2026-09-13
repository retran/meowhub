---
id: 0007
title: The household app is a small Next.js app over PostgREST, edited visually with Onlook
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0007 — The household app is a small Next.js app over PostgREST, edited visually with Onlook

## Context

Chat is how expenses go *in*. It is a poor way to look at trends: a chart in a
chat bubble is a worse chart. The requirement came from a household member, not
the owner — open something on a phone and see where the money is going — so the
bar is that it must be pleasant on an iPhone for someone with no interest in the
plumbing.

Four constraints decide what such an application can be here.

**Low-code means little code**, not building by mouse (vision principle 5). A
handful of screens over an API that already exists qualifies; a bespoke platform
does not.

**The work is done by an agent, spec-driven.** Whatever holds the screens must be
something an agent can build, review, test and rebuild, and ADR 0010 requires it
to be restorable from this repository. That disqualifies a builder whose app
definition lives only inside its own UI: those screens can only ever be clicked
together by hand.

**Appearance is the admins' call, and must not require prose.** If layout belongs
to the agent, every visual change becomes a description and a diff. That is the
one thing a visual builder genuinely does better, and it has to be answered rather
than argued away.

**Almost nothing needs to be built.** All aggregation is already obliged to live
in SQL views (ADRs 0004, 0011), and PostgREST (ADR 0014) turns those views into an
API for free. What remains is layout and fetch.

## Decision

The household app is **a small Next.js app with Tailwind CSS**, reading the
ledger from **PostgREST** (ADR 0014), served as a static build behind the same
identity provider as everything else (ADR 0032), installable to the iPhone home
screen. There is no backend of its own, no builder, and no native app.

**[Onlook](https://github.com/onlook-dev/onlook) is adopted as the visual editing
tool for it.** Apache-2.0, run locally. It opens this repository's app, runs its
dev server, and renders it on a canvas; each element carries an `oid`, so a
visual change is located in the corresponding JSX, patched into the source file
and hot-reloaded, preserving formatting and component structure. Right-clicking
an element opens its exact place in the code.

That fixes the division of labour, which is the point:

- **The agent builds and maintains the app**: SQL views, PostgREST configuration
  and row-level security, screens, data fetching, tests.
- **The owner adjusts how it looks**, by mouse, against the same codebase — not
  by describing a change and waiting for a diff.
- **Everything lands in git** as reviewable TypeScript, from either hand.

Onlook's requirements are accepted as constraints on the app, not worked around:
**Next.js and Tailwind, with styling in Tailwind classes rather than abstracted
behind a component library**, because that declarative shape is what makes visual
editing possible. This is a real limit on how the app may be written, and it is
cheap to honour at this size.

### Scope discipline

- **Read-first.** Trends, category and merchant breakdowns, balances per account,
  per-member view, month-over-month comparison.
- **The only writes are corrections** — amount, category, merchant, payment
  account on an existing transaction, merchant merges, and confirming or
  overriding a reconciliation. Capture stays in the chat.
- **Every screen is a question someone actually asked.** No speculative screens.
- **The app computes no totals.** Every number comes from a view, so the app and
  the bot's digests cannot disagree, and the app stays replaceable.
- **Provenance is visible**: a provisional, model-derived statement line must look
  different from an authoritative one (ADR 0013).

## Alternatives

| Option | Why rejected |
|---|---|
| **Budibase** | Excellent free styling — custom CSS on every component — and batteries included: auth, hosting, CRUD. But it has no agent-authoring path, only an open proposal, so every screen and every revision costs the owner an evening in the builder. White-labelling and app environment variables are paid, and its JSON export is verbose enough that review is theoretical |
| **ToolJet** | Ships an MCP server, so an agent can author its apps directly, and exports JSON with an import API — the best process fit of the builders. Rejected because the owner does not like the product, which is sufficient for the surface his household uses daily |
| **Appsmith** | Free native git version control is the strongest config-as-code story of the builders, but it has no application-level custom CSS at all, is the heaviest to run, and has the weakest mobile layouts |
| **Windmill apps** | Would consolidate the orchestrator and the UI into one tool already under consideration, and is genuinely code-first. Internal-tool aesthetics and unproven mobile polish, and it would couple two roles that are better kept separable |
| **Evidence.dev** | The purest "little code" answer — SQL plus markdown, output that reads like a designed report, everything in git. Rejected on maintenance risk: last commit February 2026 and signs of winding down. A dependency we would regret |
| **Metabase** | Actively maintained and decent on mobile, but presents as a BI product rather than the household's own app |
| **Grafana** | Dashboards provisioned from files, and an ops console on a phone |
| **A hand-written app with no visual editing** | This decision minus Onlook. Rejected because it leaves appearance changes as a conversation with the agent, which is the friction a builder was meant to remove |

## Consequences

**Good:**
- Little code, and all of it reviewable: the app is a few screens of fetch and
  layout over views that had to exist anyway.
- Both hands work on one artefact — the agent through the code, the owner through
  Onlook — with git as the single history.
- The config-as-code weak spot disappears: there is no exported bundle to
  reconcile, because the app *is* the repository (ADR 0010).
- Best available mobile result, since nothing is constrained by a builder's
  renderer.
- No paid tier anywhere in this component, and no vendor to be gated by.

**Bad, and the price we accept:**
- **This is the project's first real application code**, and the one component a
  container upgrade cannot improve. It needs tests, dependency maintenance and
  occasional framework migration, forever.
- Onlook is **early access**, and constrains the app to Next.js plus Tailwind with
  unabstracted styling. If it stalls or breaks, the app survives — it is ordinary
  code — but the visual editing does not, and appearance changes go back to being
  a conversation.
- Budibase's batteries — auth pages, CRUD scaffolding, hosting — are now ours:
  authentication comes from the proxy (ADR 0032), authorisation from row-level
  security (ADR 0014), and hosting is a static build.
- A second writer to the ledger — corrections from the app — which is why the
  audit log is enforced by database triggers (ADR 0008).

**What becomes harder to change later:**
- The framework choice, mildly — Next.js and Tailwind are now baked in by
  Onlook's requirements rather than chosen on their own merits. Keeping the app
  thin and every number in a view is what keeps even that cheap to undo.
