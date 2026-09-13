# Delivery risks

The threat model covers what defends the data; this covers what could stop the
project being useful. Each ADR carries its own price; this is the short list of
things most likely to go wrong, in one place, so that none of them is a surprise.

Ordered by expected damage, not by likelihood.

| # | Risk | Why it is real | What we already do | What we would do |
|---|---|---|---|---|
| 1 | **Nobody uses it but the person who built it** | The product's own measure of success says all three members. Two of them did not ask for it, and the daughter has the least reason of anyone | Chat-first capture, no forms, one-message entry, the app screen a member actually asked for, "what is left" as her one reason to open it | If week four shows one user, stop building slices and fix capture — a ledger with one contributor is a spreadsheet with extra steps |
| 2 | **EU-resident models read receipts badly** | ADR 0029's ladder assumes EU models get close enough. They may not, and extraction quality is the product's accuracy | Start on the best models, residency as a ladder with a quality trigger, confirmation state to absorb wrong guesses | Keep rung 1 indefinitely and say so, rather than degrading capture to satisfy a direction |
| 3 | **Onlook stalls or breaks** | Early access, and it constrains the app to Next.js plus Tailwind with unabstracted styling (ADR 0007) | The app is ordinary code that survives without it; the constraint is cheap at this size | Appearance changes go back to being a conversation with the agent; the app is unaffected |
| 4 | **The owner is the only maintainer** | One person holds the schema, the workflows and the model of the whole thing. Two admins share access, not knowledge | Everything is written down: ADRs with reasoning, specs with criteria, a rehearsed restore by the *other* admin | The rehearsal is the mitigation that matters. If the second admin cannot restore it, the bus factor is one regardless of documentation |
| 5 | **n8n's licence or product direction changes** | Source-available, not OSI, and a company decides it | Workflow JSON exported and committed; domain logic in SQL, not in nodes; Windmill named as the successor | Rewriting workflows is weeks; the ledger is untouched. That asymmetry is deliberate |
| 6 | **The confirmation queue is never drained** | It is the one recurring chore the design creates, and an unattended queue makes every total untrustworthy | Three drains — batch review, reconciliation, conservative auto-confirm — plus a ceiling alert | If the ceiling alert fires monthly, auto-confirmation is too conservative; widen it deliberately rather than ignoring the queue |
| 7 | **Statement formats differ from expectation** | The parsers cannot be written without one real export per provider, and dialects vary (spec 0007) | Fixtures from real files; the closing-balance check; PDF as the fallback path | If a provider's export is unusable, that account reconciles from PDF and says so |
| 8 | **The keyboard model outgrows the app** | ADR 0037 adds a command registry, a focus model and selection state to a component ADR 0007 kept thin | Built with the screens rather than after them | If it starts driving the architecture, cut it back to the palette and list navigation |
| 9 | **Scope grows faster than the household's patience** | Eleven slices, six candidate slices after them, and every conversation adds a good idea | Specs gate work; the ergonomics standard counts chores; candidates are written down rather than built | The measure is the chore table: if the household's monthly work exceeds a quarter of an hour, stop adding |
| 10 | **Model spend surprises** | Usage-based cost in an otherwise fixed system | Prepaid credits, a key limit, a per-call cost record, a daily alert | The cap is the control; a surprise means the cap was not set |

## The two that would end it

Most of the above are recoverable. Two are not, and both are already answered
elsewhere — listed here so the answer is not assumed:

- **Losing the ledger.** Encrypted nightly offsite backups, a monthly verified
  restore, and two custodians for every secret (ADRs 0009, 0024). The failure mode
  is not a disk; it is one person holding the restic password.
- **Losing trust in the numbers.** A figure nobody can check is a figure nobody
  acts on, and the product dies quietly. Every total states its period, its
  unconfirmed share and whether the period is reconciled; the books are
  double-entry so transfers cannot inflate spending; and the whole of
  `data-model.md` exists so two surfaces cannot disagree.
