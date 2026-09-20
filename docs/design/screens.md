# The app's screens, designed

[../standards/ui-design-process.md](../standards/ui-design-process.md) describes
the process, and here we apply it in order to the four screens and one element
that spec 0006 ships. We work steps 1 to 3 - the question, the data, the form -
in writing before any layout exists, because writing them down is what stops a
screen promising an answer the books cannot support.

No screen here computes a total. Every figure names the view it comes from, and
phase 4 of the implementation plan writes a migration for each of those views
(ADRs 0004, 0014).

---

## Tokens the screens use

ADR 0022's validated palette covers chart series, surfaces and ink, and a user
interface needs four more neutrals on top of it. We name them here as tokens,
because a neutral with no name gets invented again on every screen and the
design system falls apart.

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

Series and status colours come from ADR 0022 unchanged, in both the light and
the dark columns. No screen uses a hex value that is not one of these.

## Theme and language are the member's, not the device's

You switch both, and both belong to the member and not to the device, because
ADR 0034 says that what the household changes is data. Switch to English on your
phone and you get English on the laptop and from Meow in chat as well.

- Theme: `Как в системе`, `Светлая`, `Тёмная`. The default follows the device,
  and an explicit choice wins over the device in both directions.

We give dark its own column of token values instead of inverting the light ones,
and three things change beyond colour, which is what makes dark a design and not
a filter:

1. A filled button inverts. The primary button is dark ink on light, and on a
   dark ground a dark button disappears, so it becomes light with dark text. A
   filled checkbox and its tick invert the same way.
2. A drop shadow becomes a border. The command palette's shadow is invisible on
   a dark ground, so it carries a light hairline instead.
3. The selected-row tint turns cool. The pale blue that reads as "focused" on
   white is invisible at 4 % on near-black, so dark uses a deeper, cooler tint.

Series colours come from the dark column of the validated palette (`#3987e5` in
place of `#2a78d6`, and so on), stepped for the dark surface and validated as a
set, because lightening the light column by eye breaks the contrast the
validator checks.
- Language: Russian or English, and it moves the bot's replies with it
  (ADR 0017). Numbers and dates follow the language: `1 847,20 €` against
  `1,847.20 €`.
- On the phone both live in *Мои настройки*; on desktop they are two small
  switchers in the header, because that is where someone looks for them.
- Every string is localisable. The app holds no literal: labels, empty states,
  errors, button text, the shortcut map and the command palette all come from
  the catalogue, and a missing translation fails visibly instead of rendering a
  slug (ADR 0017).

## Screen 1 - Home

### 1. The question, and who asks it

> "What do we have, and what have we spent this month?"

Either parent asks it, most days, standing up, in under ten seconds. The
daughter opens the app for one thing only, and screen 4 has it.

We made it two questions on purpose, because the household always asks them
together and one answer on its own is useless: a balance without a spend rate is
a snapshot, and a spend rate without balances only makes people anxious.

### 2. The data, before the layout

Five figures answer the question, and each one names the view it reads.

| Figure | View | Notes |
|---|---|---|
| Each account's balance | `v_account_balance` | account, type, balance in minor units, currency, overdraft or credit limit, headroom |
| Spend this month to date | `v_period_spend` | period, total, transfers excluded, unconfirmed share |
| The same for last month | `v_period_spend` | the previous row, for the delta |
| Unconfirmed count | `v_unconfirmed_summary` | count, oldest, and whether any exceed the age ceiling |
| Whether the period is reconciled | `v_period_reconciliation` | per account and per period |

A figure that is not in that table does not go on this screen, whatever anyone
offers for it.

### 3. The form, from the data's job

- Month to date is a single headline: a hero number with a delta against last
  month. It is one value, and the form heuristic turns one value into a number
  and not a chart, so a sparkline here would decorate the screen without telling
  you anything.
- Balances are stat tiles, one per account, because each tile carries an
  identity and a magnitude and comparing the accounts against each other is not
  what you came for.
- Unconfirmed is a status row and not a figure: a count, and a way in.
- This screen carries no chart, because trends live on screen 2 and a chart here
  would turn a ten-second glance into a five-second delay.

### 4. Layout at 390 px, content first

The month's number comes first, then what the household holds, then what needs
attention.

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

The primary content sits in thumb reach, nothing on the screen needs landscape,
and the accounts list is the only part that scrolls.

### 5. Every state

The screen has eight states, and each one below says what you see in it.

| State | What it shows |
|---|---|
| Empty because new | No accounts yet: one line explaining that Meow sets the books up in chat, and nothing else. This is the first screen anyone sees |
| Empty because period | Accounts with balances, and "no spending recorded yet this month" where the hero number would be, drawn so that you can tell it apart from the row above at a glance |
| Loading | A skeleton in the shape of the content, never a spinner |
| Slow | The hero number appears as soon as the app knows it, and the balances fill in afterwards |
| Error | "Can't reach the books" and a retry. The screen shows no stale figure as if it were current |
| Unconfirmed present | The trust line sits under the hero always, even at 0 % |
| Period unreconciled | The period label says so, and no warning appears |
| Not permitted | A member who is not an admin sees no unconfirmed row, and not a disabled one either |

### 6. Both languages

We checked the longest strings in each language: «ещё не подтверждено» against
"not yet confirmed", and «из −500 лимита» against "of −500 limit". At 390 px the
trust line wraps to two lines in Russian, and the layout has to allow that
instead of truncating it. Account names are the household's own words and run
long, so a name ellipsises and a balance never does.

---

## Screen 2 - Categories

### 1. The question

> "Where is the money going, and is that changing?"

Either parent asks it about once a week, not every day, and usually right after
a digest arrives.

### 2. The data

Four figures answer it, three of them from the category views and one from the
merchant view.

| Figure | View |
|---|---|
| Spend per category for a period | `v_category_spend` |
| The same for the previous period | `v_category_spend` |
| One category across months | `v_category_spend_by_month` |
| Merchants inside one category | `v_merchant_spend` filtered |

### 3. The form

- The breakdown is horizontal bars, ordered by amount, with the values labelled
  directly on them. Each bar carries a magnitude and an identity, and bars read
  better than a pie past three slices, which this household always has.
- A category over time is a line, with months on the x axis and one series.
- Both forms also have a table view, which satisfies the light-mode relief rule
  for a bar that uses one of the three lower-contrast slots (ADR 0022).
- Each category keeps its colour across every screen and every period, so a
  filter that changes how many categories are shown must not repaint the ones
  that remain.

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

The screen handles six states. It is empty because the system is new, or empty
for the period, where it says "nothing in this category this month" and shows a
zero instead of dropping the row, so that nobody reads a missing row as a bug.
With a single month of history it draws one point and says so, because a line
through one value would invent a trend. It also has a loading state, an error
state, and a state for a category the agent created and nobody has reviewed
(ADR 0031), which the screen marks.

### 6. Both languages

Category names come from the translations table, so both languages arrive as
data and the layout does not change with them. Russian names still run longer,
so a bar label wraps under its bar instead of squeezing it.

---

## Screen 3 - Merchants

This screen asks the same question one level down, "Which shops are taking the
money?", and we gave it the same form as screen 2 on purpose: bars for the
period, a line for one merchant over months, a table view, and a stable colour
per merchant. It reads `v_merchant_spend` and `v_merchant_spend_by_month`.

Two things differ from screen 2:

- Merchant names are data and we never translate them (ADR 0017), so this screen
  looks identical in both languages, and it is where the longest names turn up.
- An admin can merge two merchants here when they look like the same shop
  (ADR 0031). It is the only action on the screen, and it restates what it will
  do before it applies anything.

---

## Screen 4 - Members

### 1. The question

> "Who spent what?"

An admin asks it now and then, and the daughter asks it for one reason: *what
have I spent, and what is left.*

### The rule that shapes this screen

This screen can do more harm than any other, because a household ledger that
ranks its members teaches people to hide expenses and argue about them, and the
persona forbids Meow to comment on spending at all (`agent-persona.md`).

So we ruled five things out:

- The screen never ranks members, never builds a leaderboard, and never orders
  them by amount. Members appear in a fixed order, and it is the same order
  every time.
- Nothing on the screen addresses a member as "you", or uses the second person
  anywhere.
- Each member keeps their own identity colour everywhere, and no colour runs on
  a scale from good to bad.
- The screen never puts two totals against each other in a way that implies a
  target.
- The daughter's own figures come first, with what is left of her allowance if
  she has one (spec 0009), because that is the only reason she opens the app.

### Data and form

The screen reads `v_member_spend` for the period and `v_member_spend_by_month`
for one member, and it draws a stat tile per member. We ruled bars out here,
because bars side by side invite a comparison and a comparison becomes a
ranking.

### States

A member who spent nothing this period shows a zero, present and unremarkable. A
member with no allowance shows spend and no "left" figure at all, because a zero
there would imply an allowance that does not exist.

---

## Element - The confirmation queue

### 1. The question

> "What did Meow record that nobody has checked?"

An admin asks it, and we built the element so that answering it takes two
minutes and not twenty (ADR 0023).

### 2. The data

It reads `v_unconfirmed`: transaction, amount, merchant, category, account,
submitter, source (text, photo, voice, statement), which fields were inferred,
and age.

### 3. The form

The list is built for approving in batches. You select rows by default, one
action approves everything selected, and you correct a row in place instead of
leaving for another screen.

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

The list marks the inferred fields, because they are the only part worth your
attention: what the member stated needs no checking.

### 5. States

An empty queue stays quiet: one line, a tick and "nothing to check", with no
celebration, because anything more would make the next full queue feel like a
reproach. When rows pass the age ceiling, the screen says so once, at the top.
A photo-derived row shows its receipt inline. When somebody else changed a row
after the list loaded, the list refreshes that row instead of overwriting their
change.

---

---

## Desktop - a different audience, not a wider phone

### The question, and who asks it

> "Let me deal with all of this at once."

An admin asks it, sitting down, with a keyboard, to drain the confirmation
queue, work through what an import flagged, fix the chart of accounts, and merge
merchants.

That admin is a different reader from the one on the phone, which spec 0006 R2
specifies for a glance: a household member, standing up, ten seconds. On desktop
the admin is working, so we design for work. Stretching the phone layout would
give a person with a mouse and both hands free forty-eight-pixel rows and
one-at-a-time confirmation.

### What changes, and what must not

| Changes | Stays the same |
|---|---|
| Persistent left navigation instead of a bottom bar | The same views, so desktop shows no figure that the phone and the bot cannot get |
| Lists become dense tables of 48 px rows and eight columns | Colour per entity, stable across surfaces |
| Keyboard operation: arrows to move, space to select, enter to approve | No capture affordance, ever (ADR 0007) |
| Two-column layouts: a table beside the panel that edits its selection | Provenance marked, unconfirmed share stated, negative normal |
| Four figures across the top in place of one hero | One primary action per screen |

We designed one breakpoint and not three. A household of three has phones and
laptops, so we draw a phone layout and a desktop layout, and designing a tablet
layout in between would be work nobody asked for.

### The keyboard model

ADR 0037 decides that you can reach everything on desktop from the keyboard, and
that the keyboard is the fast path and not a courtesy bolted onto the mouse. Two
surfaces carry the model, and we drew both:

- The command palette on `⌘K` is the one thing you have to learn. It lists every
  screen and every action available right where you are, each with its own
  shortcut beside it, so it teaches you the rest of the map instead of replacing
  it. It offers a member only what that member can do, because the palette shows
  the permissions and never enforces them a second time.
- The shortcut map on `?` exists because a shortcut nobody can discover is
  folklore and not an interface.

Every desktop screen declares its part of the map below:

| Where | Keys |
|---|---|
| Everywhere | `⌘K` palette, `/` search, `?` this map, `⌘Z` undo your last action, `Esc` back one level |
| Any list | `↑`/`↓` or `j`/`k` move, `Space` select, `⇧↑` extend, `Enter` primary action, `O` open |
| Navigation | `g` then `h` overview, `c` categories, `m` merchants, `q` queue, `s` statements, `a` accounts |
| Queue | `E` approve selected, `Enter` approve and move on, `C` fix category, `A` fix amount (admin), `⌫` delete (admin) |
| Reconciliation | `P` preview, `⌘Enter` apply, `M` match by hand, `⌘⇧Z` reverse the import |
| Accounts and categories | `N` new, `R` rename, `⌘J` merge, `D` deactivate |

Two rules matter more than the list itself. Focus never disappears: after you
approve, correct, delete or undo, it lands visibly on the next row, because a
model that drops focus after each action is slower than clicking. And none of
this reaches the phone, which keeps thumb-first targets and carries no shortcut
chrome and no palette, since a phone keyboard is there for typing a capture into
the chat.

### The four desktop screens

Desktop has four screens, and each reads the views named beside it.

| Screen | Question | Views |
|---|---|---|
| Overview | What do we have, owe, and have spent | `v_account_balance`, `v_period_spend`, `v_liability_summary`, `v_account_balance`, `v_category_spend`, `v_unconfirmed_summary` |
| Queue | What has nobody checked | `v_unconfirmed` |
| Statements and reconciliation | What will this import do | `v_statement_line`, `v_reconciliation_preview` |
| Accounts and categories | Is the chart still right | `v_account`, `v_category`, `v_account` |

The two keyboard surfaces above sit on top of all four as overlays, so they
belong to every screen and are not screens themselves.

The statements screen earns its desktop layout more than any other, because six
columns of "what will happen to this line" are unreadable on a phone and this is
the one place an admin needs the whole picture before applying something that
rewrites a month.

---

## The rest of the phone screens

We designed these to the same steps, and the last column names the decision in
each one that took more than a layout.

| Screen | Question | Views | The decision in it |
|---|---|---|---|
| Merchants | Which shops take the money | `v_merchant_spend` | Names are data and we never translate them, so the screen is identical in both languages, and the longest names turn up here |
| Search | Where was that one thing | `v_transaction_search` | It searches notes as well as merchants, which is the only reason storing notes pays for itself |
| Transaction detail | What is this, and who decided | `v_transaction_detail` | It shows where the category came from: a merchant default, a person, or a model with its prompt version. The household trusts the books because it can ask |
| Correction form | Fix what is wrong | writes only | It shows every field and offers only what this member can change: amount, date and account are admin-only, and category and project are not (ADRs 0016, 0021) |
| Statements | Is the month complete | `v_statement_import` | It labels PDF-derived rows provisional in the list itself, so you see the difference before you trust a total |
| Month and forecast | Can we afford this | `v_forecast`, `v_budget_progress`, `v_commitment` | The free-to-spend figure says what it was computed from. A budget over 100 % gets a status colour, and spending under it gets no colour at all |
| Projects, Project, Wishlist | What did it cost, and can we | `v_project_spend`, `v_project_feasibility`, `v_wish` | The project bar keeps spent, planned and wished apart, because merging them is the easiest way to mislead. An unaffordable wish reads "not yet" and never "impossible" |
| First run | What do I do with an empty system | none | The first screen anyone sees, and it hands the work to the chat instead of to a setup form |
| Settings: accounts, categories, members | Is the chart right, who can get in | `v_account`, `v_category`, `v_member` | You deactivate and never delete, everywhere. The screen marks the categories the agent invented and nobody reviewed, and offers to merge them |

## The administrative surfaces we do not design

n8n's editor, Uptime Kuma and the identity provider's own admin come from third
parties, so we design none of them and draw no artboards for them. What we do
own is that they sit behind one sign-in (ADR 0032) and that you reach them with
one keystroke from the palette (ADR 0037). The only admin screens we design here
are the ones in our own app: accounts, categories, members and profile.

## What is deliberately not designed yet

- Budgets, the forecast and the "what is left" figure wait for spec 0009, and
  screen 4's layout already leaves the slot for them.
- Projects and the wishlist wait for spec 0010, which adds a second axis to
  screens 2 and 3 instead of a new screen.
- The reconciliation review waits for spec 0007, which brings its own element.
- A capture affordance waits for nothing, because ADR 0007 rules it out
  permanently.

## The sketches

Step 4 of the process produced thirty-six artboards on six pages: the phone
screens, the forms and admin, the planning screens, the four desktop screens,
and a last page carrying the dark theme across every screen where the palette
does real work.

<https://claude.ai/code/artifact/c630ad91-20b2-487a-8086-260d9ec61f96>

They are mockups and not a prototype, so nothing in them is clickable. We left
them that way on purpose, because a sketch that costs nothing is cheap to
reject. We drew the screens that belong to later slices because their specs
already define the behaviour, and each of those screens ships with its own slice
and not before it. The artboards use the validated palette from ADR 0022 with
Golos Text and tabular figures, and the household's admin does the appearance
pass on them before we build any of it.

## Typography that does not depend on luck

Two typography constraints cost us time before we wrote them down, and
[../standards/ui-design-process.md](../standards/ui-design-process.md) now
carries both as rules:

- No layout depends on the webfont having loaded. Golos Text comes from Google
  Fonts and no PNG or PDF export embeds it, so exported text and a cold cache
  both fall back, and a fallback with different metrics moves the whole layout.
  The font stack names metric-close fallbacks, and we check every screen once
  with the webfont blocked.
- Every cell of a table row truncates. A cell with `nowrap` and no
  `text-overflow` pushes its neighbour out of the row instead of shortening
  itself, and Russian labels are long enough to make that happen.

A third rule says how to apply a fix like these: put it on the element that
needs it. A global rule changes every element, including the ones that were
already fine.

## Validation before any of this is called done

Five checks close a screen, and we run all five before calling it done.

- The screen uses the validated reference palette, and we re-run any new palette
  through the validator (ADR 0022).
- Every chart has a table view, and no chart carries an identity in colour
  alone.
- We open the screen at 390 px in both themes and both languages, and once more
  with the webfont blocked, because that is what an export and a cold cache look
  like.
- We run the Playwright journeys at phone viewport instead of reasoning about
  what they would do.
- The admin who will live with the screen does the appearance pass in Onlook.
