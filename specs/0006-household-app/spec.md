---
id: 0006
title: The household app — trends, balances, corrections and approvals
status: approved
created: 2026-09-12
updated: 2026-09-13
owner: admins
supersedes: []
---

# 0006 - The household app: trends, balances, corrections and approvals

## Problem

Chat does two jobs badly, and the two belong to different people.

A household member asked for the first and more important one: open something on
a phone and see where the money is going. A chart in a chat bubble is a worse
chart, and you answer "how has groceries moved over the year" by looking rather
than by reading a sentence.

The second job is drudgery. By this point three slices have been filling a queue
of unconfirmed, model-derived records (ADR 0023), and working through fifteen of
them in chat is slow. Corrections have the same problem: chat handles them one
message at a time, when an admin wants a list.

## Why

After this slice the household has a phone app it opens on purpose, with balances
and trends at a glance, and an admin can drain the confirmation queue in a couple
of minutes instead of a conversation.

We measure it two ways: the member who asked for the app opens it without being
reminded, and an admin stops avoiding the queue.

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
  with utility classes in the markup so that it stays editable in Onlook
  (ADR 0007).
- **R2.** The app must be installable to an iPhone home screen and usable at
  390 px without horizontal scrolling.
- **R1a.** The app must have one desktop layout as well as the phone one, with a
  persistent left navigation and a content area, and exactly one breakpoint
  between the two. We design no tablet layout.
- **R1b.** Desktop must be a working surface and not a wider phone: lists that
  are cards on the phone must be dense tables there, and the confirmation queue
  and the reconciliation review must be operable from the keyboard - move,
  select, approve - because that is what makes draining thirty records take a
  minute.
- **R1d.** On desktop, every action must be reachable without a mouse (ADR 0037).
- **R1e.** A command palette on `⌘K` must reach every screen and every action
  available in the current context, must show each entry's own shortcut, and must
  offer a member only what their role permits.
- **R1f.** Unmodified single keys must act on the focused row in any list, with
  `↑`/`↓` and `j`/`k` moving, `Space` selecting, `Enter` performing the primary
  action, `Esc` backing out and `⌘Z` undoing.
- **R1g.** A shortcut map must be reachable with `?`, and every desktop screen
  must declare its keys there and in its design.
- **R1h.** After any action, focus must land somewhere deliberate and visible,
  normally the next row. Focus lost after an action is a defect.
- **R1i.** The keyboard model must not reach the phone layout: no shortcut
  chrome, no palette, and targets stay at least 44 px.
- **R1c.** Every figure must exist on all surfaces or none, because desktop,
  phone and the bot read the same views (spec 0004, R2a).
- **R2a.** Continuous integration must build the app into static assets that the
  reverse proxy serves behind the authentication boundary, with no application
  server, no runtime rendering, and no state anywhere except the database the app
  reaches through the data API.
- **R3.** The app must hold no credential of its own and must reach data only
  through PostgREST, with authorisation enforced by row-level security
  (ADR 0014). It must never hold a database token: the proxy adds the
  Authorization header from the authenticated session (spec 0002, R16a), so the
  app's code calls a relative path.
- **R4.** The app must sit behind the authentication boundary and must have no
  login of its own (ADRs 0032, 0002-identity).
- **R5.** The app must compute no totals, because every figure comes from a SQL
  view.
- **R6.** The app must render in the member's language, and no layout may depend
  on a string's length (ADR 0017).
- **R6a.** No string in the app may be a literal. Labels, empty states, errors,
  buttons, the shortcut map and the command palette all come from the message
  catalogue, and a missing translation must fail visibly.
- **R6b.** A member must be able to switch language in the app, and the change
  must apply to the bot's replies too, because language is a property of the
  member rather than of the device or the browser session.
- **R6c.** A member must be able to switch theme between following the device,
  light and dark. An explicit choice must win over the device preference in both
  directions, and dark must use its own token values rather than an inversion
  (ADR 0022).
- **R6d.** Numbers, currency and dates must follow the chosen language -
  `1 847,20 €` against `1,847.20 €` - and no layout may assume either.
- **R6e.** Both switchers must be reachable on the phone from the member's own
  settings and on desktop from the header.
- **R7.** The app must follow the design system: tokens, shadcn/ui components,
  the chart rules, and a designed dark mode (ADR 0022).
- **R7a.** No layout may depend on a webfont having loaded: the font stack must
  name metric-close fallbacks, and every screen must hold together with the
  webfont blocked.
- **R7b.** Every cell of every table row must truncate rather than overflow, and
  every text container must be able to shrink.

### Looking

- **R8.** A home screen must show each account's balance, the month's spending to
  date, and the unconfirmed share of it.
- **R9.** A screen must show spending by category for a period, and must let a
  member drill into one category's trend across months.
- **R10.** A screen must show spending by merchant for a period.
- **R11.** A screen must show spending by member for a period.
- **R12.** Any period's figures must be comparable with the previous period.
- **R13.** A negative balance must be presented plainly, with the account's
  overdraft limit in view, because it is a normal state rather than an alarm
  (ADR 0022).
- **R14.** Every figure must state its period, and provisional or unconfirmed
  data must look different from authoritative and confirmed data (ADRs 0013,
  0023).

### Acting

- **R15.** An admin must be able to list unconfirmed records and confirm many at
  once in a single action.
- **R15a.** For an admin, the unconfirmed count and its entry point must be on
  the home screen rather than behind a tab.
- **R16.** An admin must be able to correct the amount, date, category, merchant
  or payment account of a transaction, inline in that list.
- **R17.** An admin must be able to delete a transaction after confirming, and
  the deletion must stay in the audit record.
- **R18.** Any member must be able to change a transaction's category, and the
  app must offer no control for anything they are not allowed to change
  (ADR 0016).
- **R19.** A member must be able to confirm a record they captured while it is
  unconfirmed.
- **R20.** An admin must be able to merge two merchants, with the aliases
  following the merge (ADR 0004).
- **R21.** The app must offer no way to create an expense, because capture is the
  chat's job (ADR 0007).
- **R22.** The screens must ship in this order: home, category with its trend,
  merchant, member. The unconfirmed count is part of the home screen rather than
  a screen of its own.
- **R23.** Every mutating action in the app must be undoable immediately after
  it, by the member who performed it (ADR 0036).
- **R24.** A transaction's detail must show its note, its receipt if it has one,
  and where its category came from, which is the same explanation the bot gives.
- **R25.** A member must be able to add or edit a transaction's note, because a
  note is classification rather than a financial fact (ADR 0021).

## Scope

In scope: the application shell and navigation, the reporting views it binds to,
the home screen, the category, merchant and member screens, the confirmation
queue, inline corrections, merchant merging, the PostgREST client, i18n, dark
mode, and Playwright journeys at phone viewport.

Out of scope, with the reason for each:

- Any capture form (R21), permanently rather than for now.
- Budgets, forecasts and "can we afford it", which spec 0009 covers.
- Projects and the wishlist (spec 0010), which add a second axis to these same
  screens and cost less once the screens exist.
- Statement import and its reconciliation review (spec 0007), which brings its
  own screen.
- Push notifications, because Telegram is the notification channel (ADR 0027).
- Multi-currency presentation, because the ledger is EUR only (ADR 0011).

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
      attempted against the API directly, then it fails - proven at the database,
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
      label truncates or overflows - checked at the longest realistic string in
      each language.
- [ ] **A13a.** Given the app's built bundle, when it is searched for
      user-visible text, then every such string resolves through the catalogue and
      none is a literal.
- [ ] **A13b.** Given a member who switches language in the app, when they next
      write to the bot, then Meow replies in the new language.
- [ ] **A13c.** Given a member who selects light while the device is in dark, when
      the app renders, then it is light - and the reverse also holds.
- [ ] **A13d.** Given each language, when an amount and a date render, then they
      use that language's conventions.
- [ ] **A14.** Given each screen, when rendered in light and dark mode, then the
      palette is the design system's and contrast holds - and dark uses the dark
      token column rather than inverted light values.
- [ ] **A14a.** Given each screen with the webfont blocked, when it renders, then
      nothing overflows and nothing is clipped.
- [ ] **A15.** Given the Playwright journeys, when they are run at phone viewport
      against the seeded household, then they pass - and they are run, not
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
      offers a way to create an expense - no form, no button, no route. This is a
      permanent property, so a test asserts it rather than a reviewer.
- [ ] **A18a.** Given the desktop layout at 1440 px, when every figure on it is
      compared with the same figure on the phone and from the bot, then all three
      agree, because all three read the same view.
- [ ] **A18b.** Given the desktop confirmation queue, when it is driven from the
      keyboard alone - move, select, approve - then a batch can be approved without
      touching the mouse.
- [ ] **A18c.** Given every action on every desktop screen, when each is attempted
      from the keyboard alone, then all of them are reachable - enumerated per
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

The states below are named from
[docs/standards/failure-vocabulary.md](../../docs/standards/failure-vocabulary.md).

| Situation | Expected behaviour |
|---|---|
| A category with no spending in the period | Shown as zero rather than omitted, so nobody mistakes its absence for a missing screen |
| A month still open | Figures shown with the period marked partial |
| A merchant with one transaction | Rendered, with no special case |
| A very long merchant or category name in Russian | Wraps or truncates with the full value reachable, and never breaks the layout |
| The confirmation queue is empty | A plain, quiet state, and not a celebration |
| Hundreds of unconfirmed records | The list pages, and the ceiling alert from ADR 0023 has already fired |
| A transaction edited by another admin while the list is open | The app detects the change and refreshes the list rather than writing over it |
| A session that expires while the app is open | The member authenticates again and returns to the same screen |
| Screen rotated to landscape | Works, and nothing requires it |

## Ergonomic cost

- **Who does more work:** nobody new, and an admin's existing work gets much
  cheaper, because the queue moves from a conversation to a couple of taps. This
  slice exists mostly to cut the cost of specs 0003 and 0005.
- **What queue or obligation it creates:** none of its own. This is where the
  existing queue is drained.
- **What it interrupts:** nothing, because the app sends no notifications and a
  member opens it when they choose (ADR 0027).
- **If nobody touches it for a month:** nothing degrades. The queue keeps
  draining through auto-confirmation and, from spec 0007, through reconciliation.

## Non-functional requirements

The figures below refine the shared baselines in
[docs/standards/budgets.md](../../docs/standards/budgets.md): a figure here is
stricter and says so, and where this section is silent the baseline applies.

- **Speed:** the first useful paint is fast on mobile data, and something real
  appears before everything has loaded.
- **Read-only by default:** the app's database role can write only corrections,
  confirmations and merges, and never a raw posting (ADR 0014).
- **Secrets:** the bundle carries none.
- **Accessibility:** touch targets are at least 44 px, every action is keyboard
  operable, and colour alone never carries meaning.

## Open questions

None. We have decided everything this slice needed decided, and spec 0001 and
spec 0002 list what the household still has to supply.

## Design

[docs/design/screens.md](../../docs/design/screens.md) designs the four screens
and the confirmation queue - question, view, form, layout, states, both languages
- by the process in
[docs/standards/ui-design-process.md](../../docs/standards/ui-design-process.md).
The views it names are what phase 4 of the implementation plan has to produce.

## Related

- ADRs: 0004, 0007, 0011, 0013, 0014, 0015, 0016, 0017, 0022, 0023
- Specs: 0002, 0003 and 0004 (must be done first), 0007, 0009, 0010
