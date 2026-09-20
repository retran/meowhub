# How a screen gets designed

The design system (ADR 0022) says what things look like; this document says how a
screen comes to exist, so that we design for "convenient" instead of hoping for
it.

It applies to every screen in the household app, and in a reduced form to bot
replies and digests, which are interface too.

## The rule that prevents most bad screens

A screen answers one question that somebody actually asked. Not a topic and not
an entity, but a question in the words the person used: "Where did the money go
last month." "Can we afford the deposit by March." "What did the holiday cost."

If you can't name a proposed screen as a question, it isn't designed yet. If it
answers four questions, it is four screens, or one screen with a clear primary
answer.

## The steps, in order

The ten steps below run in order, from the question the screen answers to the
evidence that closes it. Each one is cheap to do early and expensive to skip.

### 1. Write the question and who asks it

Put one line in the spec, and name who asks: the owner, the partner, or the
daughter. A screen for someone with no interest in the plumbing is a different
screen from one for the person who built it.

### 2. Name the data before the layout

Name the SQL view the screen reads (ADRs 0004, 0014). If that view doesn't exist,
the work starts with a migration and not with a component, and because the app
computes no totals of its own, a number that no view produces isn't available at
any price.

We put this step before layout because it stops a screen promising an answer the
books can't support.

### 3. Choose the form from the data's job

Use the data-visualisation method's heuristic. The job picks the form - magnitude,
identity, polarity, change over time, or a single headline - and sometimes the
answer isn't a chart at all. A monthly total is a number, and a comparison of two
months is two numbers and a delta.

### 4. Sketch at 390 px, content first

Work out the hierarchy before the layout: what the person came for, what supports
it, and what is merely available. Then place it, with the primary content in
thumb reach, nothing that requires landscape, and no horizontal scrolling except
inside a table or a chart that owns its own overflow.

For anything beyond a simple screen, sketch it visually before building it. The
`design` skill produces a canvas of artboards for exactly this, and a mockup is
cheaper to reject than a built screen.

### 5. Enumerate the states, all of them

A screen isn't designed until you have answered every state below. In practice
most rough edges are missing states rather than wrong layouts.

- Empty because new, in a household with no transactions yet. This is the first
  screen anyone sees and it is usually designed last, which is why it is usually
  bad.
- Empty because filtered, when there is no data in this period. It must not look
  like the empty-because-new case.
- Loading, and slow, which are different states: a skeleton is not a spinner.
- Error, including "the API is unreachable", always with something to do next.
- Provisional data present: model-derived statement lines have to look different
  from authoritative ones (ADR 0013), or the distinction is decorative.
- Not permitted, where a member views something only an admin can change
  (ADR 0016). The control is absent or turns into asking the owner, and never
  refuses after the tap.
- Stale: when a figure was last reconciled, if that matters to trusting it.

### 6. Check both languages, and that nothing is a literal

Check Russian and English (ADR 0017). Take the longest realistic string in each
language, in every label, and confirm that nothing truncates or reflows badly.
Russian runs materially longer than English, so a layout tuned to English breaks
silently.

### 6a. Declare the screen's keys

Every desktop screen states in its design which keys act on it and what they do,
and those keys appear in the `?` map (ADR 0037). If a screen's keys aren't
written down, it has no keys, only folklore. Check two things: no action is
mouse-only, and focus after each action lands somewhere you have named.

Phone screens declare nothing of the sort, because the keyboard model stops at
the breakpoint.

### 7. Build from the system, and add nothing new casually

Compose the screen from existing shadcn components and tokens. A new component, a
new token, or a new chart form needs a sentence in the plan saying why the
existing ones don't fit, and a commit message isn't the place for it.

### 8. Validate, do not eyeball

Run these checks on the built screen. Most of them are mechanical, and the ones
that aren't still beat looking at it and forming an impression.

- Run any new palette or palette change through the validator script, because we
  compute colour safety (ADR 0022).
- Use no hex outside the token table in `../design/screens.md`. A screen that
  needs a new neutral is proposing a token, which is a decision rather than a
  value.
- Let no meaning be carried by colour alone, and let no colour below 3:1 carry a
  mark at all.
- Look at the screen with the webfont blocked. A layout that only works once the
  font loads isn't a layout, because exports and cold caches both fall back and a
  fallback with different metrics moves everything.
- Check the structure before the styling. Unbalanced tags reparent whole blocks
  and the result looks like a font or width problem: a column that ends one
  `</div>` early turns its siblings into siblings of the *page*, which then lay
  out in a row and shrink. You can check balance, root size, and nesting depth
  mechanically, so do that first instead of guessing at CSS.
- Never fix a layout with a global rule. `min-width: 0` on everything removes the
  min-content floor that keeps columns honest, `overflow-wrap: anywhere` makes
  that floor one character wide, and together they collapse every layout in the
  file. Put the robustness on the specific child that must shrink and the
  specific cell that must truncate. When everything breaks at once, suspect the
  rule that touched everything.
- Make every cell in a table row truncate. `nowrap` without `text-overflow`
  pushes a neighbour out of the row instead of shortening itself, and Russian
  labels are long enough that it will.
- Check charts against the anti-pattern catalogue.
- Give every chart a table view, and never carry identity by colour alone.
- Check keyboard operation and focus visibility instead of assuming them.
- Open the screen and look at it, at 390 px, in light and dark, because the
  validator checks colour and not layout. Driving a real browser is part of the
  work and not a manual step: run the Playwright journeys rather than reasoning
  about them.

### 9. The admins' appearance pass

The agent builds the screen, and an admin then adjusts how it looks in Onlook,
against the same code (ADR 0007). Whatever comes out of that pass is a commit
like any other. Appearance is the admins' call, which is why we gave up a builder
without giving up mouse editing.

### 10. Close it with evidence

Close the spec's acceptance criteria for a screen the way we close every other
criterion, by naming a passing test (ADR 0015). For screens that test is a
Playwright journey at phone viewport against the seeded household, plus a
recorded manual pass for the things automation can't judge, such as whether the
screen is actually pleasant.

## Worked example

[../design/screens.md](../design/screens.md) takes the four screens of spec 0006
through these steps. It includes the one screen that needed a rule of its own
before anyone could lay it out: the per-member view, where a ranking would
produce exactly the behaviour the product is trying to avoid.

## Standing rules

These rules hold for every screen, and a review checks them.

- One primary action per screen. If two things compete, one of them isn't
  primary, and on desktop the primary action is what `Enter` does.
- Every number states its period and its provenance, because nobody can check or
  trust a total that states neither.
- The app never asks for capture. A form for entering an expense means the bot is
  missing a capability (ADR 0007), and the fix is a spec for the bot.
- No accounting vocabulary. No member reads "posting", "debit", or "chart of
  accounts" (vision principle 10), on a screen or in an error.
- Money is not a status. Expenses aren't red, and only a genuine problem - over
  budget, a missed commitment, or a projected overdraft - gets status colour,
  with an icon and a label (ADR 0022).
- Negative is normal. Show an overdrawn account clearly, with its limit, and
  don't raise an alarm about it.
- A screen can be boring. Someone reads it in a shop, in thirty seconds, without
  having asked to learn a new interface, so glanceable beats clever.

## Applying this to the bot

Bot replies and digests are interface under the same rules in reduced form, and
Meow speaks them, in the voice specified in
[agent-persona.md](agent-persona.md).

- One question per reply, and a confirmation is one short message.
- Plain language, in the member's language, with no accounting words.
- Every figure carries its period.
- A failure says what happens next - "I've kept this and will ask again" - and
  never drops anything silently (vision principle 6).
- A digest is designed the way a screen is: it answers a named question and it
  states its period.
