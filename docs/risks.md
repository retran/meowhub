# Delivery risks

The threat model covers what defends the data, and this document covers what
could stop the project being useful. Each ADR carries its own price; here we
keep the short list of what is most likely to go wrong, in one place, so that
none of it surprises us later.

We ordered the table by how much damage each risk would do, not by how likely it
is. The last column says what we would do if the risk arrived tomorrow.

| # | Risk | Why it is real | What we already do | What we would do |
|---|---|---|---|---|
| 1 | Nobody uses it but the person who built it | The product measures its own success by all three members using it. Two of them did not ask for it, and the daughter has less reason than anyone | Chat-first capture, no forms, one-message entry, the app screen a member actually asked for, and "what is left" as her one reason to open it | If week four shows one user, stop building slices and fix capture, because a ledger with one contributor is a spreadsheet with extra steps |
| 2 | EU-resident models read receipts badly | ADR 0029's ladder assumes EU models get close enough, they might not, and extraction quality is what makes the product accurate | Start on the best models, treat residency as a ladder with a quality trigger, and let confirmation state absorb a wrong guess | Stay on rung 1 indefinitely and say so out loud, because degrading capture to satisfy a direction costs the household more than the direction gains |
| 3 | Onlook stalls or breaks | It is in early access, and it holds the app to Next.js plus Tailwind with unabstracted styling (ADR 0007) | The app is ordinary code and survives without Onlook, so the constraint stays cheap at this size | Appearance changes go back to being a conversation with the agent, and the app itself does not change |
| 4 | The owner is the only maintainer | One person holds the schema, the workflows and the model of the whole system. The two admins share access, and they do not share knowledge | We write everything down: ADRs with their reasoning, specs with their criteria, and a restore rehearsed by the *other* admin | The rehearsal is the mitigation that decides this one. If the second admin cannot restore the system, the bus factor is one however much we wrote down |
| 5 | n8n's licence or product direction changes | Its licence is source-available and not OSI-approved, and one company decides where it goes | We export and commit the workflow JSON, keep the domain logic in SQL instead of in nodes, and name Windmill as the successor | Rewriting the workflows costs weeks and leaves the ledger untouched, and we built it that way on purpose |
| 6 | The confirmation queue is never drained | It is the one recurring chore the design creates, and an unattended queue makes every total untrustworthy | Three things drain it - batch review, reconciliation and conservative auto-confirm - and a ceiling alert fires when they do not | If the ceiling alert fires every month, auto-confirmation is too conservative, so widen it deliberately instead of ignoring the queue |
| 7 | Statement formats differ from expectation | Nobody can write the parsers without one real export per provider, and the dialects vary (spec 0007) | Fixtures taken from real files, the closing-balance check, and PDF as the fallback path | If a provider's export is unusable, that account reconciles from PDF and the screens say so |
| 8 | The keyboard model outgrows the app | ADR 0037 adds a command registry, a focus model and selection state to a component ADR 0007 deliberately kept thin | We build it with the screens instead of after them | If it starts driving the architecture, cut it back to the palette and list navigation |
| 9 | Scope grows faster than the household's patience | Eleven slices, six candidate slices after them, and every conversation adds another good idea | Specs gate the work, the ergonomics standard counts the chores, and we write candidates down instead of building them | The chore table is the measure: if the household's monthly work passes a quarter of an hour, stop adding |
| 10 | Model spend surprises us | The cost is usage-based in a system whose other costs are fixed | Prepaid credits, a key limit, a per-call cost record, and a daily alert | The cap is the control, so a surprise means we did not set the cap |

## The two that would end it

The household can recover from most of the risks above. Two of them it could
not, and other documents already answer both, so we list the answers here rather
than assume them.

- Losing the ledger. Encrypted nightly offsite backups, a monthly verified
  restore, and two custodians for every secret answer it (ADRs 0009, 0024). The
  failure that ends the project is not a dead disk; it is one person holding the
  restic password.
- Losing trust in the numbers. A figure nobody can check is a figure nobody acts
  on, and the product then dies quietly. Every total states its period, its
  unconfirmed share and whether the period is reconciled, the books are
  double-entry so transfers cannot inflate spending, and `data-model.md` exists
  so that two surfaces cannot disagree.
