# How a screen gets designed

The design system (ADR 0022) says what things look like. This says how a screen
comes to exist, so that "convenient" is a property we design for rather than hope
for.

It applies to every screen in the household app and, in a reduced form, to bot
replies and digests — which are also interface.

## The rule that prevents most bad screens

**A screen answers one question that somebody actually asked.** Not a topic, not
an entity — a question, in the words the person used. "Where did the money go
last month." "Can we afford the deposit by March." "What did the holiday cost."

If a proposed screen cannot be named as a question, it is not designed yet. If it
answers four questions, it is four screens or one screen with a clear primary
answer.

## The steps, in order

### 1. Write the question and who asks it

One line in the spec. Include who: the owner, the partner, the daughter. A screen
for someone with no interest in the plumbing is a different screen from one for
the person who built it.

### 2. Name the data before the layout

Name the SQL view the screen reads (ADRs 0004, 0014). If it does not exist, the
work starts with a migration, not with a component — and the app **computes no
totals of its own**, so a number that no view produces is not yet available at any
price.

This step is deliberately before layout: it is what stops a screen promising an
answer the books cannot support.

### 3. Choose the form from the data's job

Use the data-visualisation method's heuristic. Magnitude, identity, polarity,
change over time, or a single headline — the job picks the form, and **sometimes
the answer is not a chart**. A monthly total is a number. A comparison of two
months is two numbers and a delta.

### 4. Sketch at 390 px, content first

Hierarchy before layout: what is the one thing the person came for, what supports
it, what is merely available. Then place it — primary content in thumb reach,
nothing requiring landscape, no horizontal scrolling except inside a table or a
chart that owns its own overflow.

For anything beyond a simple screen, sketch it visually before building it — the
`design` skill produces a canvas of artboards for exactly this, and a mockup is
cheaper to reject than a built screen.

### 5. Enumerate the states, all of them

A screen is not designed until these are answered. Most rough edges in practice
are missing states, not wrong layouts:

- **Empty because new** — a household with no transactions yet. This is the first
  screen anyone sees, and it is usually designed last, which is why it is usually
  bad.
- **Empty because filtered** — no data in this period, which must not look like
  the empty-because-new case.
- **Loading**, and **slow** — they are different; a skeleton is not a spinner.
- **Error**, including "the API is unreachable" — with something to do next.
- **Provisional data present** — model-derived statement lines must look
  different from authoritative ones (ADR 0013), or the distinction is decorative.
- **Not permitted** — a member viewing something only an admin may change
  (ADR 0016). The affordance is absent or asks-the-owner, never a refusal after
  the tap.
- **Stale** — when a figure was last reconciled, if that matters to trusting it.

### 6. Check both languages, and that nothing is a literal

Russian and English (ADR 0017). Take the longest realistic string in each, in
every label, and confirm nothing truncates or reflows badly. Russian runs
materially longer than English; a layout tuned to English breaks silently.

### 6a. Declare the screen's keys

Every **desktop** screen states, in its design, which keys act on it and what they
do — and those keys appear in the `?` map (ADR 0037). A screen whose keys are not
written down does not have keys; it has folklore. Two checks: no action is
mouse-only, and focus after each action lands somewhere named.

Phone screens declare nothing of the sort: the keyboard model stops at the
breakpoint.

### 7. Build from the system, and add nothing new casually

Compose from existing shadcn components and tokens. A new component, a new token
or a new chart form needs a sentence saying why the existing ones do not fit — in
the plan, not in a commit message.

### 8. Validate, do not eyeball

- Any new palette or palette change goes through the validator script; colour
  safety is computed (ADR 0022).
- **No hex outside the token table** in `../design/screens.md`. A screen that
  needs a new neutral is proposing a token, which is a decision, not a value.
- **No meaning carried by colour alone** — and no colour below 3:1 carrying a
  mark at all.
- **Look at it with the webfont blocked.** A layout that only works when the font
  loads is not a layout: exports and cold caches both fall back, and a fallback
  with different metrics moves everything.
- **Check the structure before the styling.** Unbalanced tags reparent whole
  blocks, and the result looks like a font or width problem: a column that ends
  one `</div>` early turns its siblings into siblings of the *page*, which then
  lay out in a row and shrink. Balance, root size and nesting depth are
  checkable mechanically; do that first and stop guessing at CSS.
- **Never fix a layout with a global rule.** `min-width: 0` on everything removes
  the min-content floor that keeps columns honest, and `overflow-wrap: anywhere`
  makes that floor one character wide — together they collapse every layout in
  the file. Robustness goes on the specific child that must shrink and the
  specific cell that must truncate. When everything breaks at once, suspect the
  rule that touched everything.
- **Every cell in a table row truncates.** `nowrap` without `text-overflow`
  pushes a neighbour out of the row rather than shortening itself, and Russian
  labels are long enough that it will.
- Charts are checked against the anti-pattern catalogue.
- Every chart has a table view; identity is never colour alone.
- Keyboard operation and focus visibility are checked, not assumed.
- The screen is opened and looked at, at 390 px, in light and dark — the
  validator checks colour, not layout. Driving a real browser is part of the
  work, not a manual step: the Playwright journeys are run, not reasoned about.

### 9. The admins' appearance pass

The agent builds the screen; an admin adjusts how it looks in Onlook, against
the same code (ADR 0007). Anything that comes out of that pass is a commit like
any other. Appearance is explicitly the admins' call — this step is why the
project gave up a builder without giving up mouse editing.

### 10. Close it with evidence

The spec's acceptance criteria for the screen are closed the way every other
criterion is: a named passing test (ADR 0015) — for screens, a Playwright journey
at phone viewport against the seeded household — plus a recorded manual pass for
the things automation cannot judge, like whether it is actually pleasant.

## Worked example

The four screens of spec 0006 are taken through these steps in
[../design/screens.md](../design/screens.md) — including the one screen that
needed a rule of its own before it could be laid out at all: the per-member view,
where a ranking would produce exactly the behaviour the product is trying to
avoid.

## Standing rules

These hold for every screen, and reviews check them:

- **One primary action per screen.** If two things compete, one is not primary —
  and on desktop it is what `Enter` does.
- **Every number states its period and its provenance.** A total with neither is
  a number nobody can check or trust.
- **The app never asks for capture.** A form for entering an expense is a sign the
  bot is missing a capability (ADR 0007); the fix is a spec for the bot.
- **No accounting vocabulary.** No member reads "posting", "debit" or "chart of
  accounts" (vision principle 10). Not on screens, not in errors.
- **Money is not a status.** Expenses are not red; only genuine problems —
  over budget, a missed commitment, a projected overdraft — get status colour,
  with an icon and a label (ADR 0022).
- **Negative is normal.** An overdrawn account is a state to show clearly with its
  limit, not an alarm.
- **A screen may be boring.** Glanceable beats clever; this is read in a shop, in
  thirty seconds, by someone who did not ask to learn a new interface.

## Applying this to the bot

Bot replies and digests are interface under the same rules, reduced — and they
are spoken by Meow, whose voice is specified in
[agent-persona.md](agent-persona.md):

- One question per reply; confirmations are one short message.
- Plain language, the member's language, no accounting words.
- Every figure carries its period.
- A failure says what happens next — "I've kept this and will ask again", never a
  silent drop (vision principle 6).
- A digest is designed the same way a screen is: it answers a named question, and
  it states its period.
