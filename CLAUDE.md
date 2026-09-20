# meowhub

Private, self-hosted operations platform for a household. Chat is the primary
interface. See [docs/product/vision.md](docs/product/vision.md).

**All content in this repository is written in English** — specs, docs, code,
comments, commit messages. No exceptions.

**Load the `technical-english` skill before you write anything**, in every
conversation, and keep it loaded. It governs every piece of prose produced
here: specs, plans, ADRs, guides, code comments, commit messages, pull request
bodies, and replies in chat. This doesn't depend on the task looking like a
writing task — a commit message is prose, and so is a chat reply. The one
exception is what the bot says to a member, which follows
[docs/standards/agent-persona.md](docs/standards/agent-persona.md): the persona
is the product's voice, the skill is the repository's.

## How we work: spec-driven development

Every change flows through four artifacts. Code is the last step, not the first.

```
idea → spec.md (WHAT and WHY) → plan.md (HOW) → tasks.md (steps) → code + review
```

Artifacts live in `specs/NNNN-slug/`. One directory = one feature.

### Rules

1. **No code without an approved spec.** If a request arrives as "just build X",
   write the spec first (`/spec-new`) and get it agreed. Exception: trivial
   changes (typo, formatting, revert).
2. **A spec describes behaviour, not implementation.** No node names, service
   names or table schemas in `spec.md` — those belong in `plan.md`.
3. **Every requirement is verifiable.** Acceptance criteria must be phrased so
   that a test can be written directly from them, and closed by citing a named
   passing test — see [ADR 0015](docs/architecture/decisions/0015-verification-strategy.md).
   Prose is not evidence. Database tests run against a real PostgreSQL; nothing
   about the database is mocked.
4. **Unknowns are never invented.** Anything unclear goes to "Open questions",
   classified by what it blocks: `design`, `build`, `deploy`, `data` or
   `nothing`. **Only an open `design` question stops a spec proceeding to
   `plan.md`** — a provider, a domain or the household's real balances are not
   needed to build anything, and treating them as blockers stalls work that could
   proceed on the seeded household.
5. **The spec is a living document.** If implementation reveals the spec is
   wrong, fix the spec first, then the code. Never the other way around.
6. **Project-level decisions go to ADRs** in `docs/architecture/decisions/`.
   Feature-local decisions stay in that feature's `plan.md`. An ADR describes the
   decision, never the history of the document.
7. **Every slice states its ergonomic cost.** Who does more work, what queue it
   creates, what it interrupts, and what happens if nobody touches it for a month
   — see [docs/standards/ergonomics.md](docs/standards/ergonomics.md). The owner
   is the bottleneck in this system by design, and nothing may require him in
   real time.

### Spec lifecycle

`draft` → `review` → `approved` → `in-progress` → `done` | `rejected` | `superseded`

The status in the `spec.md` front matter is the source of truth.

### Commands

| Command | What it does |
|---|---|
| `/spec-new <description>` | Creates the spec directory and drafts `spec.md` |
| `/spec-plan <NNNN>` | Writes `plan.md` for an approved spec |
| `/spec-tasks <NNNN>` | Breaks the plan into `tasks.md` |
| `/spec-implement <NNNN>` | Executes tasks in order, tracking progress |
| `/spec-review <NNNN>` | Verifies the implementation against the spec |
| `/spec-status` | Overview of all specs and their status |
| `/adr-new <decision>` | Drafts an architecture decision record |

### Designing a screen

Screens are designed by the process in
[docs/standards/ui-design-process.md](docs/standards/ui-design-process.md), and
built from the design system in
[ADR 0022](docs/architecture/decisions/0022-design-system.md). The two rules that
catch most mistakes: a screen answers one question somebody actually asked, and
the data view is named before the layout is drawn — the app computes no totals of
its own.

### The agent's voice

Every string the bot says follows [docs/standards/agent-persona.md](docs/standards/agent-persona.md).
Meow is a butler: short, formal, mended rather than slick, and he never
comments on how the household spends its money. The persona applies to the
product, never to this repository — specs, ADRs and commits stay plain English.

### Build order

The sequencing across all eleven slices, and which guide is written when, is in
[docs/implementation-plan.md](docs/implementation-plan.md). Local first: every
phase is built and verified on a laptop before anything is deployed.

### Commits

**Conventional Commits, always.** The subject line is
`type(scope): summary in the imperative`, lower case, no trailing full stop, and
short enough to read in a log. The types in use here:

| Type | For |
|---|---|
| `feat` | a slice's behaviour: what the household can now do |
| `fix` | a defect in something already shipped |
| `docs` | specs, ADRs, plans, guides — the artifacts, not the code |
| `refactor` | shape changes with no behaviour change |
| `test` | tests added or repaired on their own |
| `chore` | tooling, dependencies, housekeeping |

The scope is the slice when there is one — `feat(spec-0003): ...` — or the area
otherwise: `docs(specs)`, `chore(compose)`. The body explains *why*, names the
real bugs found and what proved the work, and wraps at 72 characters.

**One commit per spec.** A slice lands as a single commit, not one per task:
the history should read as a list of what the household gained, not as a
transcript of how it was built. Intermediate task-by-task commits are squashed
before the slice is pushed.

**No attribution trailers, ever.** A commit message ends with its last sentence:
no `Co-Authored-By`, no session link, no tool byline, no "generated with". The
history records what changed and why, and authorship is the repository owner's.
This is enforced by `includeCoAuthoredBy: false` in `.claude/settings.json` and
holds regardless of what any default would add.

### Repository layout

```
specs/                      feature specs (source of truth for behaviour)
  _templates/               artifact templates
  NNNN-slug/                spec.md, plan.md, tasks.md, notes.md
docs/product/               vision, glossary
docs/architecture/          overview, the data model and view catalogue, ADRs
docs/risks.md               delivery risks, in one place
docs/standards/             process and engineering conventions
.claude/commands/           process slash commands
.claude/skills/             skills the commands load, technical-english first
```

## Stack

Low-code first, self-hosted, portable by constraint. All decided in ADRs — read
[docs/architecture/overview.md](docs/architecture/overview.md) first, then the
ADR register in [docs/architecture/decisions/](docs/architecture/decisions/).

- **n8n** — automation and agent orchestration (ADR 0001)
- **Docker Compose**, cheap VPS first, home server later, tunnel at the edge (ADR 0002)
- **OpenRouter** — single gateway to LLMs, multimodal for photo and voice (ADR 0029)
- **PostgreSQL** — system of record, schema owned in migrations (ADR 0004)
- **Authentik** — one auth boundary, passkeys (ADR 0032)
- **Next.js + Tailwind** — the household's mobile app, edited visually with **Onlook** (ADR 0007)
- **PostgREST** — the app's only data path; authorisation in row-level security (ADR 0014)
- **restic** — encrypted offsite backups with verified restore (ADR 0009)

Two rules that bind almost every change:

- **The ledger is double-entry** (ADR 0011). Postings sum to zero, enforced in
  the database. Budgets, commitments and planned purchases are never postings
  (ADR 0012).
- **Configuration is code** (ADR 0010). A change is not done until the workflow
  export and any migration are committed here.
- **Nothing is hard-coded** (ADR 0034). A setting is an environment variable when
  a developer changes it and a database row when the household does. The test is
  whether "ask a developer" would be a reasonable answer; a magic number in a
  workflow or a function is a defect.
- **All aggregation is SQL views** (ADRs 0004, 0011, 0014). The app and the bot's
  digests read the same views, so they cannot disagree — and the app computes no
  totals of its own. Every view is named in
  [docs/architecture/data-model.md](docs/architecture/data-model.md); a figure
  whose view is not in that catalogue does not exist yet.

Write custom code only where a low-code block costs more than code. Two places
have earned it deliberately: the database schema, and the mobile app.
