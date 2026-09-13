---
id: 0006
title: The household app — trends, balances, corrections and approvals
status: review
created: 2026-09-12
updated: 2026-09-12
owner: admins
supersedes: []
---

# 0006 — The household app: trends, balances, corrections and approvals

## Problem

Two things the chat cannot do well, and they belong to different people.

A household member asked for the one that matters most: open something on a phone
and *see* where the money is going. A chart in a chat bubble is a worse chart, and
"how has groceries moved over the year" is a question you answer by looking rather
than by reading a sentence.

The other is drudgery. By this point three slices have been filling a queue of
unconfirmed, model-derived records (ADR 0023), and chat is a terrible place to
work through fifteen of them. Corrections are the same shape: one at a time in
messages, when what is wanted is a list.

## Why

After this slice the household has a phone app it opens on purpose: balances and
trends at a glance, and an admin can drain the confirmation queue in a couple of
minutes rather than a conversation.

The measure: the member who asked for it opens it without being reminded, and the
queue stops being the thing an admin avoids.

## Users and scenarios

- **A member** wants to open the app on their phone and see, in one screen, what
  the household has and what it has been spending.
- **A member** wants to tap a category and see its trend across months.
- **An admin** wants to review a list of unconfirmed records and approve most of
  them in one action.
- **An admin** wants to fix a wrong amount, category, merchant or payment account
  without composing a sentence.
- **A member** wants to re-file their own spending into the right category.
- **An admin** wants to know which figures are still unconfirmed before trusting
  a total.

## Requirements

### Shape and access

- **R1.** The app must be a small Next.js application with Tailwind CSS, styled
  with utility classes in the markup so it stays editable in Onlook (ADR 0007).
- **R2.** It must be installable to an iPhone home screen and usable at 390 px
  without horizontal scrolling.
- **R1a.** There must be **one desktop layout** as well as the phone one — a
  persistent left navigation and a content area — and exactly one breakpoint
  between them. No tablet layout is designed.
- **R1b.** Desktop is the **working surface**, not a wider phone: lists that are
  cards on the phone are dense tables there, and the confirmation queue and the
  reconciliation review must be **operable from the keyboard** — move, select,
  approve — because that is what makes draining thirty records take a minute.
- **R1d.** On desktop, **no action may be reachable only by mouse** (ADR 0037).
- **R1e.** A command palette on `⌘K` must reach every screen and every action
  available in the current context, showing each entry's own shortcut, and must
  offer a member only what their role permits.
- **R1f.** Unmodified single keys must act on the focused row in any list, with
  `↑`/`↓` and `j`/`k` moving, `Space` selecting, `Enter` performing the primary
  action, `Esc` backing out and `⌘Z` undoing.
- **R1g.** A shortcut map must be reachable with `?`, and every desktop screen
  must declare its keys there and in its design.
- **R1h.** After any action, focus must land somewhere deliberate and visibly —
  normally the next row. Losing focus after an action is a defect.
- **R1i.** The keyboard model must not reach the phone layout: no shortcut
  chrome, no palette, and targets stay at least 44 px.
- **R1c.** No figure may exist on one surface and not the others. Desktop, phone
  and the bot read the same views (spec 0004, R2a).
- **R2a.** It must be built in continuous integration into static assets, and
  served by the reverse proxy behind the authentication boundary — no application
  server, no runtime rendering, and nothing for the app to hold state in besides
  the database it reaches through the data API.
- **R3.** It must hold no credential of its own and must reach data only through
  PostgREST, with authorisation enforced by row-level security (ADR 0014). It must
  never hold a database token: the proxy adds the Authorization header from the
  authenticated session (spec 0002, R16a), so the app's code simply calls a
  relative path.
- **R4.** It must sit behind the authentication boundary, with no login of its own
  (ADRs 0032, 0002-identity).
- **R5.** It must compute no totals: every figure comes from a SQL view.
- **R6.** It must render in the member's language, and no layout may depend on a
  string's length (ADR 0017).
- **R6a.** **No string in the app may be a literal.** Labels, empty states,
  errors, buttons, the shortcut map and the command palette all come from the
  message catalogue, and a missing translation must fail visibly.
- **R6b.** A member must be able to switch **language** in the app, and the change
  must apply to the bot's replies too — it is a property of the member, not of the
  device or the browser session.
- **R6c.** A member must be able to switch **theme** between following the device,
  light and dark; an explicit choice must win over the device preference in both
  directions, and dark must use its own token values rather than an inversion
  (ADR 0022).
- **R6d.** Numbers, currency and dates must follow the chosen language —
  `1 847,20 €` against `1,847.20 €` — and no layout may assume either.
- **R6e.** Both switchers must be reachable on the phone from the member's own
  settings and on desktop from the header.
- **R7.** It must follow the design system: tokens, shadcn/ui components, the
  chart rules, and a designed dark mode (ADR 0022).
- **R7a.** No layout may depend on a webfont having loaded: the font stack must
  name metric-close fallbacks, and every screen must hold together with the
  webfont blocked.
- **R7b.** Every cell of every table row must truncate rather than overflow, and
  no text container may be unable to shrink.

### Looking

- **R8.** A home screen must show each account's balance, the month's spending to
  date, and the unconfirmed share of it.
- **R9.** A screen must show spending by category for a period, and allow drilling
  into one category's trend across months.
- **R10.** A screen must show spending by merchant for a period.
- **R11.** A screen must show spending by member for a period.
- **R12.** Any period's figures must be comparable with the previous period.
- **R13.** A negative balance must be presented plainly, with the account's
  overdraft limit in view — it is a normal state, not an alarm (ADR 0022).
- **R14.** Every figure must state its period, and provisional or unconfirmed data
  must be visually distinct from authoritative and confirmed data (ADRs 0013,
  0023).

### Acting

- **R15.** An admin must be able to list unconfirmed records and confirm many at
  once in a single action.
- **R15a.** For an admin, the unconfirmed count and its entry point must be on the
  home screen, not behind a tab.
- **R16.** An admin must be able to correct the amount, date, category, merchant
  or payment account of a transaction, inline in that list.
- **R17.** An admin must be able to delete a transaction, with confirmation, and
  the deletion must remain in the audit record.
- **R18.** Any member must be able to change a transaction's category, and must
  not be offered controls for anything they may not change (ADR 0016).
- **R19.** A member must be able to confirm a record they captured while it is
  unconfirmed.
- **R20.** An admin must be able to merge two merchants, with the aliases
  following the merge (ADR 0004).
- **R21.** The app must offer no way to create an expense. Capture is the chat's
  job (ADR 0007).
- **R22.** The screens must ship in this order: home, category with its trend,
  merchant, member. The unconfirmed count is part of the home screen, not a
  screen of its own.
- **R23.** Every mutating action in the app must be undoable immediately after it,
  by the member who performed it (ADR 0036).
- **R24.** A transaction's detail must show its note, its receipt if it has one,
  and where its category came from — the same explanation the bot gives.
- **R25.** A member must be able to add or edit a transaction's note, which is
  classification rather than a financial fact (ADR 0021).

## Scope

**In scope:** the application shell and navigation, the reporting views it binds
to, the home screen, the category, merchant and member screens, the confirmation
queue, inline corrections, merchant merging, the PostgREST client, i18n, dark
mode, and Playwright journeys at phone viewport.

**Out of scope (and why):**
- Any capture form (R21) — permanently, not for now.
- Budgets, forecasts and "can we afford it" (spec 0009).
- Projects and the wishlist (spec 0010) — they add a second axis to these same
  screens, which is cheaper once these exist.
- Statement import and its reconciliation review (spec 0007), which brings its
  own screen.
- Push notifications. Telegram is the notification channel (ADR 0027).
- Multi-currency presentation. EUR only (ADR 0011).

## Acceptance criteria

- [ ] **A1.** Given a seeded household, when the home screen is opened at 390 px,
      then each account's balance matches the sum of its postings, and the month's
      total and unconfirmed share match the corresponding views.
- [ ] **A2.** Given the same data, when a figure in the app is compared with the
      same figure from the bot's digest, then they are identical.
- [ ] **A3.** Given a category screen, when a category is opened, then its
      month-by-month trend renders, with a legend where there are two or more
      series and a table view available.
- [ ] **A4.** Given an account with a negative balance, when the home screen
      renders, then the balance is shown as negative with the overdraft limit
      visible, and it is not coloured as an error.
- [ ] **A5.** Given a period containing provisional statement lines and
      unconfirmed records, when its figures render, then both are visually
      distinguishable from confirmed, authoritative data.
- [ ] **A6.** Given twelve unconfirmed records, when an admin selects ten and
      approves, then all ten become confirmed in one action, each with the actor
      and route recorded.
- [ ] **A7.** Given an unconfirmed record with a wrong amount, when an admin edits
      it inline, then the transaction is corrected and the audit record shows both
      states.
- [ ] **A8.** Given a member who is not an admin, when they open the queue, then
      they see it, can change categories, can confirm their own captures, and are
      offered no control that would edit an amount, date or account.
- [ ] **A9.** Given a member who is not an admin, when a correction of an amount is
      attempted against the API directly, then it fails — proven at the database,
      not by the absence of a button.
- [ ] **A10.** Given two merchants that are the same shop, when an admin merges
      them, then their transactions and aliases point at one merchant and no
      figure changes.
- [ ] **A11.** Given a new household with no data, when the app is opened, then
      every screen shows a deliberate empty state that explains what to do next,
      distinct from a filtered-empty state.
- [ ] **A12.** Given the API unreachable, when the app is opened, then it says so
      with something to do next, and shows no stale figure as though it were
      current.
- [ ] **A13.** Given each screen, when rendered in Russian and in English, then no
      label truncates or overflows — checked at the longest realistic string in
      each language.
- [ ] **A13a.** Given the app's built bundle, when it is searched for
      user-visible text, then every such string resolves through the catalogue and
      none is a literal.
- [ ] **A13b.** Given a member who switches language in the app, when they next
      write to the bot, then Meow replies in the new language.
- [ ] **A13c.** Given a member who selects light while the device is in dark, when
      the app renders, then it is light — and the reverse also holds.
- [ ] **A13d.** Given each language, when an amount and a date render, then they
      use that language's conventions.
- [ ] **A14.** Given each screen, when rendered in light and dark mode, then the
      palette is the design system's and contrast holds — and dark uses the dark
      token column rather than inverted light values.
- [ ] **A14a.** Given each screen with the webfont blocked, when it renders, then
      nothing overflows and nothing is clipped.
- [ ] **A15.** Given the Playwright journeys, when they are run at phone viewport
      against the seeded household, then they pass — and they are run, not
      reasoned about.
- [ ] **A16.** Given a clean checkout, when the app is built by the documented
      command, then the output is static assets the proxy serves, and requesting
      them unauthenticated returns nothing.
- [ ] **A17.** Given a correction made in the app, when the member undoes it, then
      the previous state is restored by a compensating change and both appear in
      the audit record.
- [ ] **A18.** Given a transaction created from a photo with a note, when its
      detail is opened, then the note, the receipt and the origin of its category
      are all shown.
- [ ] **A19.** Given every screen in the app, when each is inspected, then none
      offers a way to create an expense — no form, no button, no route. This is a
      permanent property, so it is asserted by a test rather than by review.
- [ ] **A18a.** Given the desktop layout at 1440 px, when every figure on it is
      compared with the same figure on the phone and from the bot, then all three
      agree, because all three read the same view.
- [ ] **A18b.** Given the desktop confirmation queue, when it is driven from the
      keyboard alone — move, select, approve — then a batch can be approved without
      touching the mouse.
- [ ] **A18c.** Given every action on every desktop screen, when each is attempted
      from the keyboard alone, then all of them are reachable — enumerated per
      screen, not sampled.
- [ ] **A18d.** Given the palette opened by a member who is not an admin, when its
      entries are listed, then no admin-only action appears; and given the same
      action attempted directly against the API, then it fails at the database.
- [ ] **A18e.** Given a row approved with a keystroke, when the list updates, then
      focus is on the next row and visible.
- [ ] **A18f.** Given the phone layout, when it is inspected, then it presents no
      shortcut hints and no palette.
- [ ] **A20.** Given a transaction, when an admin deletes it from the app and
      confirms, then it no longer affects any balance and the deletion with its
      final state is in the audit record.

## Edge cases and failures

States are named from [docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A category with no spending in the period | Shown as zero rather than omitted, so its absence is not mistaken for a missing screen |
| A month still open | Figures shown with the period marked partial |
| A merchant with one transaction | Rendered; no special case |
| A very long merchant or category name in Russian | Wraps or truncates with the full value reachable; never breaks the layout |
| The confirmation queue is empty | A plain, quiet state — not a celebration |
| Hundreds of unconfirmed records | The list pages, and the ceiling alert from ADR 0023 has already fired |
| A transaction edited by another admin while the list is open | The change is detected and the list refreshes rather than writing over it |
| A session that expires while the app is open | Re-authentication, then back to the same screen |
| Screen rotated to landscape | Works; nothing requires it |

## Ergonomic cost

- **Who does more work:** nobody new, and an admin's existing work gets much
  cheaper — the queue moves from a conversation to a couple of taps. This slice
  exists mostly to *reduce* the cost of spec 0003 and 0005.
- **What queue or obligation it creates:** none of its own. It is where the
  existing queue is drained.
- **What it interrupts:** nothing. There are no notifications; the app is pulled,
  never pushed (ADR 0027).
- **If nobody touches it for a month:** nothing degrades. The queue keeps draining
  through auto-confirmation and, from spec 0007, reconciliation.

## Non-functional requirements

These refine the shared baselines in [docs/standards/budgets.md](../../docs/standards/budgets.md); a figure here is stricter and says so, or the baseline applies.

- **First useful paint is fast on mobile data**, and something real appears before
  everything has loaded.
- **Read-only by default:** the app's database role may write only corrections,
  confirmations and merges — never a raw posting (ADR 0014).
- **No secrets in the bundle.**
- **Accessibility:** touch targets at least 44 px, keyboard operable, identity
  never conveyed by colour alone.

## Open questions

None. Everything this slice needed decided has been decided; what the household
must still supply is listed in spec 0001 and spec 0002.

## Design

The four screens and the confirmation queue are designed — question, view, form,
layout, states, both languages — in
[docs/design/screens.md](../../docs/design/screens.md), following
[docs/standards/ui-design-process.md](../../docs/standards/ui-design-process.md).
The views named there are what phase 4 of the implementation plan must produce.

## Related

- ADRs: 0004, 0007, 0011, 0013, 0014, 0015, 0016, 0017, 0022, 0023
- Specs: 0002, 0003 and 0004 (must be done first), 0007, 0009, 0010
