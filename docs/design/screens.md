# The app's screens, designed

The process is in [../standards/ui-design-process.md](../standards/ui-design-process.md)
and this is it applied, in order, to the four screens and one element that spec
0006 ships. Steps 1 to 3 — the question, the data, the form — are done here in
writing, before any layout exists, because that is what stops a screen promising
an answer the books cannot support.

Nothing here computes a total. Every figure names the view it comes from, and
each of those views is a migration in phase 4 of the implementation plan
(ADRs 0004, 0014).

---

## Tokens the screens use

ADR 0022's validated palette covers chart series, surfaces and ink. A UI needs
four more neutrals. Unnamed, they get invented per screen, which is how a design
system decays. They are tokens:

| Token | Light | Dark | Role |
|---|---|---|---|
| `--ground` | `#f4f3f1` | `#141413` | The page behind the cards |
| `--surface-1` | `#fcfcfb` | `#1a1a19` | Cards, bars, the navigation |
| `--muted` | `#f0efec` | `#2a2a28` | Inactive chips, table headers, toggle tracks |
| `--track` | `#e8e7e3` | `#2f2f2c` | The unfilled part of a progress bar |
| `--row-selected` | `#f7f9fd` | `#16202c` | The focused row in a table |
| `--text-primary` | `#0b0b0b` | `#ffffff` | |
| `--text-secondary` | `#52514e` | `#c3c2b7` | |
| `--border` | `rgba(11,11,11,0.07)` | `rgba(255,255,255,0.10)` | |

Series and status colours come from ADR 0022 unchanged, light and dark columns
both. Nothing in a screen may use a hex that is not one of these.

## Theme and language are the member's, not the device's

Both are switchable, and both are **properties of the member** (ADR 0034: the
household changes it, so it is data). A member who switches to English on their
phone gets English on the laptop and from Meow in chat.

- **Theme**: `Как в системе` · `Светлая` · `Тёмная`. The default follows the
  device; an explicit choice wins over it in both directions.

**Dark is its own token column, not an inversion** — and three things change
beyond colour, which is what makes it a design rather than a filter:

1. **A filled button inverts.** The primary button is dark ink on light; on a dark
   ground a dark button disappears, so it becomes light with dark text. The same
   goes for a filled checkbox and its tick.
2. **A drop shadow becomes a border.** The command palette's shadow is invisible
   on a dark ground; it carries a light hairline instead.
3. **The selected-row tint turns cool.** The pale blue that reads as "focused" on
   white is invisible at 4 % on near-black, so dark uses a deeper, cooler tint.

Series colours come from the validated palette's **dark column** (`#3987e5`
rather than `#2a78d6`, and so on) — stepped for the dark surface and validated as
a set, not lightened by eye.
- **Language**: Russian or English, and it moves the bot's replies with it
  (ADR 0017). Numbers and dates follow the language: `1 847,20 €` against
  `1,847.20 €`.
- **On the phone** both live in *Мои настройки*; **on desktop** they are two small
  switchers in the header, because that is where someone looks for them.
- **Everything is localisable.** No string in the app is a literal: labels,
  empty states, errors, button text, the shortcut map and the command palette all
  come from the catalogue, and a missing translation fails visibly rather than
  rendering a slug (ADR 0017).

## Screen 1 — Home

### 1. The question, and who asks it

> **"What do we have, and what have we spent this month?"**

Asked by either parent, most days, standing up, in under ten seconds. The
daughter opens it for one thing only, which is not on this screen (see screen 4).

It is deliberately two questions, because they are always asked together and
answering only one is useless: a balance without a spend rate is a snapshot, and
a spend rate without balances is an anxiety.

### 2. The data, before the layout

| Figure | View | Notes |
|---|---|---|
| Each account's balance | `v_account_balance` | account, type, balance in minor units, currency, overdraft or credit limit, headroom |
| Spend this month to date | `v_period_spend` | period, total, transfers excluded, unconfirmed share |
| The same for last month | `v_period_spend` | the previous row, for the delta |
| Unconfirmed count | `v_unconfirmed_summary` | count, oldest, and whether any exceed the age ceiling |
| Whether the period is reconciled | `v_period_reconciliation` | per account and per period |

If a figure is not in that table, it is not on this screen at any price.

### 3. The form, from the data's job

- **Month to date is a single headline** — a hero number with a delta against
  last month. It is one value; the form heuristic says that is a number, not a
  chart, and a sparkline here would decorate rather than inform.
- **Balances are stat tiles**, one per account, because they are identity plus
  magnitude and the comparison between them is not the point.
- **Unconfirmed is a status row**, not a figure: a count and a way in.
- **No chart on this screen.** Trends are screen 2; putting one here would make
  the ten-second glance a five-second delay.

### 4. Layout at 390 px, content first

Hierarchy: the month's number, then what we have, then what needs attention.

```
┌──────────────────────────────┐
│ Октябрь · до 14-го           │  period, and that it is partial
│                              │
│        1 847,20 €            │  hero: month to date
│      ▲ 12 % к сентябрю       │  delta, neutral colour, not red
│      8 % ещё не подтверждено │  the trust line
│                              │
│ ─ Счета ────────────────────  │
│  ABN AMRO · текущий          │
│  2 340,10 €                  │  tile
│  ING · текущий               │
│  −120,00 €  из −500 лимита   │  negative is normal, limit in view
│  Наличные            85,00 € │
│  ICS карта         −412,55 € │  liability
│ ─────────────────────────────│
│  ● 12 записей без проверки   │  admins only; tap → queue
└──────────────────────────────┘
```

Primary content sits in thumb reach; nothing requires landscape; the accounts
list is the only part that scrolls.

### 5. Every state

| State | What it shows |
|---|---|
| Empty because new | No accounts yet: one line explaining that Meow sets the books up in chat, and nothing else. This is the first screen anyone sees |
| Empty because period | Accounts with balances, and "no spending recorded yet this month" where the hero number would be — visibly different from the case above |
| Loading | Skeleton in the shape of the content, not a spinner |
| Slow | The hero number appears as soon as it is known; balances fill in after |
| Error | "Can't reach the books" and a retry; **no stale figure shown as current** |
| Unconfirmed present | The trust line under the hero, always, even at 0 % |
| Period unreconciled | Stated on the period label, not as a warning |
| Not permitted | A member who is not an admin sees no unconfirmed row at all — not a disabled one |

### 6. Both languages

Longest strings checked: «ещё не подтверждено» against "not yet confirmed",
«из −500 лимита» against "of −500 limit". The trust line wraps to two lines in
Russian at 390 px and must be allowed to, not truncated. Account names are the
household's own words and can be long — they ellipsise, the balance never does.

---

## Screen 2 — Categories

### 1. The question

> **"Where is the money going, and is that changing?"**

Asked by either parent, weekly rather than daily, usually after a digest.

### 2. The data

| Figure | View |
|---|---|
| Spend per category for a period | `v_category_spend` |
| The same for the previous period | `v_category_spend` |
| One category across months | `v_category_spend_by_month` |
| Merchants inside one category | `v_merchant_spend` filtered |

### 3. The form

- **The breakdown is horizontal bars**, ordered by amount, with values direct
  labelled. Magnitude plus identity, and bars beat a pie the moment there are
  more than three slices — which there always are.
- **A category over time is a line**, months on the x axis, one series.
- **The table view exists** for both, which also satisfies the light-mode relief
  rule where a bar uses one of the three lower-contrast slots (ADR 0022).
- Colour is per category, stable across every screen and every period: a filter
  that changes the category count must not repaint the survivors.

### 4. Layout

```
┌──────────────────────────────┐
│ [Октябрь] [Сентябрь] [Год]   │  period as buttons, not a dropdown
│                              │
│ Продукты      ████████ 612 € │  bars, sorted, direct-labelled
│ Дом           █████    431 € │
│ Транспорт     ███      198 € │
│ Кафе          ██       147 € │
│ …            ▾ ещё 6         │
│                              │
│ Всего        1 847,20 €      │  the same figure as home, same view
└──────────────────────────────┘
        tap a category ↓
┌──────────────────────────────┐
│ Продукты · 12 месяцев        │
│   ╭─╮   ╭╮                   │  one line, months
│ ──╯ ╰───╯╰──                 │
│ Средне 580 € · сейчас 612 €  │
│ ─ Где ──────────────────────  │
│  Albert Heijn         380 €  │
│  Jumbo                142 €  │
│ [Таблица]                    │  the table view, always reachable
└──────────────────────────────┘
```

### 5. States

Empty-new; empty-period ("nothing in this category this month" — zero shown, not
the row omitted, so its absence is not mistaken for a bug); a single month of
history, where the line is one point and says so rather than drawing a line
between one value; loading; error; a category with an unreviewed flag from the
agent (ADR 0031) marked as such.

### 6. Both languages

Category names come from the translations table, so both languages are data, not
layout — but Russian names run longer and the bar labels must wrap under the bar
rather than squeeze it.

---

## Screen 3 — Merchants

The same question one level down — **"Which shops are taking the money?"** — and
deliberately the same form as screen 2: bars for the period, a line for one
merchant over months, the table view, colour stable per merchant. Data:
`v_merchant_spend`, `v_merchant_spend_by_month`.

Two differences that matter:

- **Merchant names are data, never translated** (ADR 0017), so this screen is
  identical in both languages and is where long names are most likely.
- **A merge is offered here**, for admins, when two merchants look like the same
  shop (ADR 0031) — the one action on this screen, and it restates before
  applying.

---

## Screen 4 — Members

### 1. The question

> **"Who spent what?"**

Asked by an admin occasionally, and by the daughter for one reason: *what have I
spent, and what is left.*

### The rule that shapes this screen

This is the screen most capable of doing harm. A household ledger that ranks its
members produces exactly the behaviour the product does not want — hiding
expenses, or arguing about them — and the persona forbids commenting on spending
at all (`agent-persona.md`).

So, explicitly:

- **No ranking, no leaderboard, no ordering by amount.** Members appear in a
  fixed order, always the same one.
- **No "you" framing** and no second person anywhere on it.
- **Colour is the member's own identity colour**, stable everywhere, never a
  scale from good to bad.
- **No totals compared against each other** in a way that implies a target.
- **The daughter's own view is the primary thing here**: hers first, with what is
  left of her allowance if one exists (spec 0009), because that is the only
  reason she opens the app at all.

### Data and form

`v_member_spend` for the period, `v_member_spend_by_month` for one member. Form:
stat tiles per member — deliberately *not* bars, because bars side by side are a
comparison and a comparison is a ranking.

### States

A member with no spending this period shows zero, present and unremarkable. A
member with no allowance shows spend without a "left" figure rather than a zero
that implies one.

---

## Element — The confirmation queue

### 1. The question

> **"What did Meow record that nobody has checked?"**

Asked by an admin, and the whole point of the element is that answering it takes
two minutes and not twenty (ADR 0023).

### 2. The data

`v_unconfirmed` — transaction, amount, merchant, category, account, submitter,
source (text, photo, voice, statement), which fields were inferred, age.

### 3. The form

A list optimised for **batch approval**: selection is the default interaction,
approval is one action for everything selected, and correcting is inline rather
than a detour to another screen.

### 4. Layout

```
┌──────────────────────────────┐
│ Без проверки · 12            │
│ [Выбрать все]   [Принять 8]  │  batch is the primary action
│                              │
│ ☑ 24,40 € Albert Heijn       │
│   Продукты* · ING · Ольга    │  * = inferred, the only thing to check
│ ☑  3,50 € Coffee Company     │
│   Кафе* · ABN* · Андрей      │
│ ☐ 89,00 € неизвестно         │  photo-derived, nothing inferred safely
│   [фото] нужна категория     │
└──────────────────────────────┘
```

Inferred fields are marked, because they are the only part worth a human's
attention; what the member stated needs no checking.

### 5. States

Empty queue: quiet, one line, **no celebration** — a tick and "nothing to check"
is enough, and anything more makes the next full queue feel like a reproach.
Over the age ceiling: stated at the top, once. Photo-derived rows show the
receipt inline. A row changed by someone else since the list loaded refreshes
rather than overwriting.

---

---

## Desktop — a different audience, not a wider phone

### The question, and who asks it

> **"Let me deal with all of this at once."**

Asked by an admin, sitting down, with a keyboard: drain the confirmation queue,
work through what an import flagged, fix the chart of accounts, merge merchants.

That is a different audience from the phone. The phone was specified for a glance
— a household member, standing up, ten seconds (spec 0006, R2). **Desktop is the
working surface**, and treating it as a stretched phone would produce exactly the
wrong thing: forty-eight-pixel rows and one-at-a-time confirmation for a person
with a mouse and both hands free.

### What changes, and what must not

| Changes | Stays the same |
|---|---|
| Persistent left navigation instead of a bottom bar | **The same views.** No figure exists on desktop that the phone and the bot cannot get |
| Lists become dense tables — 48 px rows, eight columns | Colour per entity, stable across surfaces |
| Keyboard operation: arrows to move, space to select, enter to approve | No capture affordance, ever (ADR 0007) |
| Two-column layouts: a table beside the panel that edits its selection | Provenance marked, unconfirmed share stated, negative normal |
| Four figures across the top rather than one hero | One primary action per screen |

**One breakpoint, not three.** Phone and desktop, nothing in between designed
deliberately — a household of three has phones and laptops, and inventing a
tablet layout would be work nobody asked for.

### The keyboard model

Desktop is keyboard-first in the sense ADR 0037 decides: **nothing is reachable
only by mouse**, and the fast path is the keyboard rather than a courtesy added to
it. Two surfaces carry it and both are drawn:

- **The command palette** on `⌘K` — the one thing anyone has to learn. It lists
  every screen and every action available right here, each with its own shortcut
  beside it, so it teaches the rest of the map instead of replacing it. It offers
  a member only what a member may do; the palette is a view of the permissions,
  never a second gate.
- **The shortcut map** on `?` — because an undiscoverable shortcut is folklore,
  not an interface.

The map itself, which every desktop screen must declare its part of:

| Where | Keys |
|---|---|
| Everywhere | `⌘K` palette · `/` search · `?` this map · `⌘Z` undo your last action · `Esc` back one level |
| Any list | `↑`/`↓` or `j`/`k` move · `Space` select · `⇧↑` extend · `Enter` primary action · `O` open |
| Navigation | `g` then `h` overview, `c` categories, `m` merchants, `q` queue, `s` statements, `a` accounts |
| Queue | `E` approve selected · `Enter` approve and move on · `C` fix category · `A` fix amount (admin) · `⌫` delete (admin) |
| Reconciliation | `P` preview · `⌘Enter` apply · `M` match by hand · `⌘⇧Z` reverse the import |
| Accounts and categories | `N` new · `R` rename · `⌘J` merge · `D` deactivate |

Two rules that matter more than the list. **Focus is never lost**: after approve,
correct, delete or undo, focus lands on the next row, visibly — a model that drops
focus after each action is slower than clicking. And **the phone has none of
this**: thumb-first targets, no shortcut chrome, no palette. A phone keyboard is
for typing a capture into the chat.

### The four desktop screens

| Screen | Question | Views |
|---|---|---|
| Overview | What do we have, owe, and have spent | `v_account_balance`, `v_period_spend`, `v_liability_summary`, `v_account_balance`, `v_category_spend`, `v_unconfirmed_summary` |
| Queue | What has nobody checked | `v_unconfirmed` |
| Statements · reconciliation | What will this import do | `v_statement_line`, `v_reconciliation_preview` |
| Accounts and categories | Is the chart still right | `v_account`, `v_category`, `v_account` |

Plus the two keyboard surfaces above, which are overlays rather than screens and
belong to every one of them.

The statements screen earns desktop more than any other: six columns of "what
will happen to this line" is unreadable on a phone, and it is the one place an
admin needs the whole picture before applying something that rewrites a month.

---

## The rest of the phone screens

Designed to the same steps; the ones that needed a decision rather than a layout
are called out.

| Screen | Question | Views | The decision in it |
|---|---|---|---|
| Merchants | Which shops take the money | `v_merchant_spend` | Names are data, never translated, so the screen is identical in both languages — and long names are likeliest here |
| Search | Where was that one thing | `v_transaction_search` | Searches notes as well as merchants, which is the only reason notes are worth storing |
| Transaction detail | What is this, and who decided | `v_transaction_detail` | Shows **where the category came from** — merchant default, a person, or a model with its prompt version. Trust is built from being able to ask |
| Correction form | Fix what is wrong | writes only | Shows every field but offers only what the member may change: amount, date and account are admin-only, category and project are not (ADRs 0016, 0021) |
| Statements | Is the month complete | `v_statement_import` | PDF-derived rows are labelled provisional **in the list**, so the distinction is visible before anyone trusts a total |
| Month and forecast | Can we afford this | `v_forecast`, `v_budget_progress`, `v_commitment` | The free-to-spend figure states what it was computed from. Budgets over 100 % use a status colour; spending under it does not get a colour at all |
| Projects · Project · Wishlist | What did it cost, and can we | `v_project_spend`, `v_project_feasibility`, `v_wish` | The project bar separates **spent, planned and wished** — merging them is the obvious way to mislead. An unaffordable wish is "not yet", never "impossible" |
| First run | What do I do with an empty system | none | The first screen anyone sees, and it hands the work to the chat rather than to a setup form |
| Settings · accounts, categories, members | Is the chart right, who can get in | `v_account`, `v_category`, `v_member` | Deactivation instead of deletion, everywhere. Unreviewed categories the agent invented are marked and offered for merging |

## The administrative surfaces we do not design

n8n's editor, Uptime Kuma and the identity provider's own admin are third-party
interfaces. We do not design them and there are no artboards for them: what we
own is that they sit behind one sign-in (ADR 0032) and that reaching them is one
keystroke from the palette (ADR 0037). The only admin surfaces designed here are
the ones in our own app — accounts, categories, members and profile.

## What is deliberately not designed yet

- Budgets, forecast and the "what is left" figure — spec 0009, and screen 4's
  layout leaves the slot for it.
- Projects and the wishlist — spec 0010, which adds a second axis to screens 2
  and 3 rather than a new screen.
- The reconciliation review — spec 0007, which brings its own element.
- Any capture affordance. Permanently (ADR 0007).

## The sketches

Step 4 of the process: thirty-six artboards on six pages, the last being the
dark theme across the screens where the palette actually does work — the phone screens,
the forms and admin, the planning screens, and the four desktop screens:

**<https://claude.ai/code/artifact/c630ad91-20b2-487a-8086-260d9ec61f96>**

They are mockups, not a prototype: nothing is clickable, and that is deliberate at
this stage — the point is to be cheap to reject. Screens belonging to later slices
are drawn because their specs already define the behaviour; they ship with their
slice, not before it. They use the validated palette
from ADR 0022 with Golos Text and tabular figures, and they are where the
household's admin does the appearance pass before any of it is built.

## Typography that does not depend on luck

Two constraints, both learned the hard way and both now rules in
[../standards/ui-design-process.md](../standards/ui-design-process.md):

- **No layout may depend on the webfont having loaded.** Golos Text comes from
  Google Fonts and is not embedded in PNG or PDF export, so exported text and a
  cold cache both fall back — and a fallback with different metrics moves
  everything. The stack names metric-close fallbacks, and every screen is checked
  once with the webfont blocked.
- **Every cell of a table row truncates.** `nowrap` without `text-overflow` pushes
  its neighbour out of the row instead of shortening itself, and Russian labels
  are long enough that it will.

And one about how to fix such things: **robustness goes on the specific element
that needs it.** A global rule is a change to every element, including the ones
that were fine.

## Validation before any of this is called done

- The palette is the validated reference palette; a new one is re-run through the
  validator (ADR 0022).
- Every chart has a table view; identity is never colour alone.
- Checked at 390 px in both themes and both languages, by opening it — **and once
  with the webfont blocked**, because that is what an export and a cold cache look
  like.
- Playwright journeys at phone viewport, run rather than reasoned about.
- Then the appearance pass in Onlook, by the admin who will live with it.
