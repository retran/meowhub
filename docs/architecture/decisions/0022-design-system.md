---
id: 0022
title: Design system — tokens, shadcn/ui components, and the data-visualisation method as a standard
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0022 - Design system: tokens, shadcn/ui components, and the data-visualisation method as a standard

## Context

ADR 0007 makes the household app a small Next.js app with Tailwind that the
owner edits visually through Onlook. That leaves a gap: there is no builder's
default theme to inherit, so every screen would invent its own spacing, colours
and chart style, and the app would drift into looking like three different apps.

Three constraints decide what a design system can be here:

1. Onlook needs the styling to stay in the markup, because it edits by finding
   an element's JSX and patching its Tailwind classes. A component library that
   hides styling behind props, such as MUI, Chakra or Mantine, would make most of
   the app invisible to the tool the owner uses to change how it looks.
2. The app is charts: trends, breakdowns, balances over time. Chart decisions
   about form, colour and labelling are most of the visual design, and they are
   the ones taste most often gets wrong.
3. The app runs in two languages (ADR 0017), so no layout can depend on a
   string's length, and provenance matters (ADR 0013), so provisional data has
   to look different from authoritative data.

## Decision

### Tokens first, in CSS custom properties

Colour, spacing, radius, typography and elevation are **design tokens** declared
as CSS custom properties and exposed through the Tailwind theme. A screen
references a role, such as `--surface-1`, `--text-secondary` or `--series-3`, and
never a raw hex value.

We design dark mode rather than flipping the light one, so it has its own token
values, defined under both the `prefers-color-scheme` media query and an
explicit theme attribute, which lets a toggle win in both directions.

### Components: shadcn/ui on Radix

We use **shadcn/ui** as the component layer: we copy its components into this
repository as source, style them with Tailwind classes in the markup, and build
on Radix primitives.

We chose it for the first constraint above. The classes stay where Onlook can
see them, and a component is ordinary code that the agent can change and an
admin can restyle. Radix underneath supplies keyboard behaviour, focus
management and ARIA semantics, which are tedious to hand-roll and embarrassing
to get wrong.

We add no styling abstraction layers: no CSS-in-JS, no `styled()` wrappers, and
no variant systems that compute classes at runtime. Utility classes go in the
JSX, and `cva` handles component variants at most.

### Charts: the data-visualisation method is binding

The project adopts the house data-visualisation method as a standard that
screens have to follow. Its rules bite most often on these points:

- Pick the form from the data's job. Sometimes the answer is a stat tile or a
  single hero number instead of a chart, because a monthly total is a number.
- Use one axis and never a dual-axis chart, so two measures of different scale
  become two charts or an indexed comparison.
- Let colour follow the entity and never its rank, so changing a filter doesn't
  repaint the series that survive.
- Make a sequential scale one hue from light to dark, and a diverging scale two
  hues with a neutral grey midpoint. No rainbows.
- Show a legend whenever there are two or more series, with selective direct
  labels rather than a number on every point, so identity never rests on colour
  alone.
- Give every chart a hover layer by default and a table view, which also serves
  screen readers and the print case.
- Keep marks thin, keep the grid and axes recessive, and draw text in the text
  tokens rather than in the series colour.

We render with **Recharts**, because it is React, it is SVG, it themes from our
tokens, and shadcn ships a chart wrapper for it. visx is the escape hatch if a
bespoke form is ever genuinely needed.

### The palette is the validated reference palette

We have no brand to match, so we adopt the method's reference palette unchanged.
We validated it rather than assuming it, by running it in both modes:

- light, surface `#fcfcfb`: lightness band, chroma floor, CVD separation (worst
  adjacent pair delta E 9.1) and normal-vision floor (delta E 19.6) all pass;
- dark, surface `#1a1a19`: all five checks pass, including contrast.

Two results of that run are rules rather than notes:

- Light mode carries a contrast warning on three slots - aqua, yellow and
  magenta, all below 3:1 on the light surface. Where a screen uses one of them,
  the relief rule applies: visible direct labels or the table view. Nobody can
  dismiss it.
- Scatter, bubble and small-multiple forms cap at three series, because the full
  eight don't clear the all-pairs floors. Past three series, fold the rest into
  "Other" or facet the chart.

We re-run the validator on any future palette change before it ships.

### Money is not a status

Status colours - good, warning, serious, critical - are reserved for states:
over budget, a missed commitment, a projected overdraft, a provisional statement
line. They always ship with an icon and a label, and never as colour alone.

Spending is not a state, so we don't paint expenses red or income green. A
household's groceries are not an error, and colouring them as one turns every
report into an accusation. Amounts use the text and categorical tokens, and only
a genuine problem gets a status colour.

### Money, number and date formatting

- We store amounts as integer minor units (ADR 0011) and format them at the
  edge, in EUR by default, following the member's language conventions, because
  a Dutch-style comma decimal is what they type and what they read.
- Negative balances are explicit and not merely red: an overdraft reads as a
  negative amount with its limit in reach, because that is a normal state here.
- Every number states its period and its provenance, because a total without
  "October, from statements" is a number nobody can check.
- Dates render in the member's language, and the household timezone is the only
  clock.

### Layout and accessibility

- We design mobile first at 390 px, nothing requires landscape, and the primary
  content sits in thumb reach.
- Touch targets are at least 44 px.
- No layout depends on string length. We check both languages, because Russian
  runs materially longer than English.
- Contrast, focus visibility and keyboard operation are requirements. We inherit
  them from Radix where we can and test them where we can't.

## Alternatives

| Option | Why rejected |
|---|---|
| MUI, Chakra or Mantine | Batteries included, but they hide styling behind props and theme objects, which would blind Onlook and hand appearance back to the agent, contradicting ADR 0007 |
| Tailwind alone, no component layer | Fewer dependencies, and every dialog, menu and tooltip re-implemented by hand, accessibility included. Radix exists because that goes wrong |
| A bespoke component library | The most control and the most work, for three people and a handful of screens |
| Charts by hand in SVG or D3 | Total control, and far more code than Recharts for the forms we need, while the chart rules stay the standard either way |
| Chart.js or ECharts | Canvas-based, so charts stop being inspectable DOM and stop inheriting tokens cleanly |
| Inventing a palette to taste | The failure the method exists to prevent. Colourblind-safety and contrast are computable, so we compute them |
| Red expenses, green income | Conventional in finance apps and wrong here, because it marks ordinary life as failure and spends the status palette on something that is not a status |
| Skipping dark mode | The household reads this on phones at night, and a flipped light theme looks broken while a designed one doesn't |

## Consequences

**Good:**
- Screens look like one app, and nobody maintains a style guide by hand to get
  that.
- The agent writes components and an admin restyles them in Onlook, because the
  classes sit in the markup where both can reach them.
- Chart decisions come out of a procedure with checks, so they're right by
  construction instead of by argument.
- Accessibility and colourblind-safety are properties of the system rather than
  of whoever built the screen.

**Bad, and the price we accept:**
- We copy shadcn components instead of depending on them, so upstream fixes
  don't arrive on their own and each component is ours to maintain once pasted.
- Tailwind classes in the markup make JSX noisy to read, which is the direct
  cost of keeping it editable in Onlook.
- The chart rules will sometimes forbid the obvious thing, such as a dual axis
  or a fourth colour in a scatter, and the alternative takes longer to build.
- The relief rule on three light-mode slots means some charts have to carry
  labels or a table view they would otherwise skip.

**What becomes harder to change later:** tokens spread through every screen, so
renaming a role means a sweep across all of them. Referencing roles instead of
hex values is what makes revaluing a role free, and revaluing is the change that
actually happens.
