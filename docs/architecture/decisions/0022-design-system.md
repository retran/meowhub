---
id: 0022
title: Design system — tokens, shadcn/ui components, and the data-visualisation method as a standard
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0022 — Design system: tokens, shadcn/ui components, and the data-visualisation method as a standard

## Context

ADR 0007 makes the household app a small Next.js app with Tailwind, edited
visually by the owner through Onlook. That leaves a gap: with no builder's default
theme to inherit, every screen would otherwise invent its own spacing, colours and
chart style, and the app would drift into looking like three different apps.

Three constraints shape what a design system can be here:

1. **Onlook needs styling to stay in the markup.** Its editing works by locating
   an element's JSX and patching its Tailwind classes. A component library that
   hides styling behind props — MUI, Chakra, Mantine — would make most of the app
   invisible to the tool the owner uses to change how it looks.
2. **The app is charts.** Trends, breakdowns, balances over time. Chart decisions
   — form, colour, labelling — are most of the visual design, and they are the
   ones most often got wrong by taste.
3. **Two languages** (ADR 0017), so no layout may depend on a string's length,
   and **provenance matters** (ADR 0013), so provisional data must be visually
   distinguishable from authoritative data.

## Decision

### Tokens first, in CSS custom properties

Colour, spacing, radius, typography and elevation are **design tokens** declared
as CSS custom properties and exposed through the Tailwind theme. Screens reference
roles — `--surface-1`, `--text-secondary`, `--series-3` — never raw hex.

**Dark mode is designed, not flipped**: its own token values, defined under both
the `prefers-color-scheme` media query and an explicit theme attribute, so a
toggle wins in both directions.

### Components: shadcn/ui on Radix

**shadcn/ui** is the component layer: components are **copied into this
repository as source**, styled with Tailwind classes in the markup, built on Radix
primitives.

It is chosen for exactly the constraint above — the classes stay where Onlook can
see them, and a component is ordinary code the agent can change and an admin can
restyle. Radix underneath supplies keyboard behaviour, focus management and ARIA
semantics, which are tedious to hand-roll and embarrassing to get wrong.

**No styling abstraction layers**: no CSS-in-JS, no `styled()` wrappers, no
variant systems that compute classes at runtime. Utility classes in the JSX,
`cva` for component variants at most.

### Charts: the data-visualisation method is binding

The project adopts the house data-visualisation method as a **standard, not a
suggestion**. Its rules that bite most often here:

- **Pick the form from the data's job.** Sometimes the answer is a stat tile or a
  single hero number, not a chart. A monthly total is a number.
- **One axis. Never a dual-axis chart.** Two measures of different scale become
  two charts or an indexed comparison.
- **Colour follows the entity, never its rank.** Changing a filter must not
  repaint the surviving series.
- **Sequential is one hue light to dark; diverging is two hues with a neutral
  grey midpoint.** No rainbows.
- **A legend is always present for two or more series**, with selective direct
  labels — never a number on every point. Identity is never colour alone.
- **A hover layer by default**, and a table view of every chart, which also
  serves screen readers and the print case.
- **Thin marks, recessive grid and axes, text in text tokens** — never in the
  series colour.

**Rendering library: Recharts** — React, SVG, themeable from our tokens, and
shadcn ships a chart wrapper for it. visx is the escape hatch if a bespoke form is
ever genuinely needed.

### The palette is the validated reference palette

We have no brand to match, so the method's reference palette is adopted unchanged,
and it was **validated rather than assumed** — run in both modes:

- light, surface `#fcfcfb`: lightness band, chroma floor, CVD separation (worst
  adjacent pair ΔE 9.1) and normal-vision floor (ΔE 19.6) all pass;
- dark, surface `#1a1a19`: all five checks pass, including contrast.

Two consequences are rules, not notes:

- **Light mode carries a contrast warning on three slots** (aqua, yellow,
  magenta, all below 3:1 on the light surface). Where those are used, the
  **relief rule applies**: visible direct labels or the table view. Not
  dismissable.
- **Scatter, bubble and small-multiple forms cap at three series**, because the
  full eight do not clear the all-pairs floors. Past three: fold into "Other" or
  facet.

Any future palette change is re-run through the validator before it ships.

### Money is not a status

Status colours — good, warning, serious, critical — are **reserved for states**:
over budget, a missed commitment, a projected overdraft, a provisional statement
line. They always ship with an icon and a label, never colour alone.

**Spending is not a state.** Expenses are not painted red and income is not
painted green: a household's groceries are not an error, and colouring them as one
turns every report into an accusation. Amounts use text and categorical tokens;
only a genuine problem gets a status colour.

### Money, number and date formatting

- Amounts are stored as integer minor units (ADR 0011) and formatted at the edge,
  in EUR by default, using the member's language conventions — a Dutch-style
  comma decimal is what they will type, and what they read.
- **Negative balances are explicit**, not merely red: an overdraft reads as a
  negative amount with its limit in reach, because that is a normal state here.
- **Every number states its period and its provenance.** A total without "October,
  from statements" is a number nobody can check.
- Dates render in the member's language; the household timezone is the only clock.

### Layout and accessibility

- **Mobile first at 390 px**, and nothing may require landscape. The primary
  content sits in thumb reach.
- **Touch targets at least 44 px.**
- **No layout depends on string length** — both languages are checked, and
  Russian runs materially longer than English.
- Contrast, focus visibility and keyboard operation are requirements, inherited
  from Radix where possible and tested where not.

## Alternatives

| Option | Why rejected |
|---|---|
| MUI, Chakra or Mantine | Batteries included, and they hide styling behind props and theme objects — which would blind Onlook and hand appearance back to the agent. Directly contradicts ADR 0007 |
| Tailwind alone, no component layer | Fewer dependencies, and every dialog, menu and tooltip re-implemented by hand, accessibility included. Radix exists precisely because that goes wrong |
| A bespoke component library | The most control and the most work, for three people and a handful of screens |
| Charts by hand in SVG or D3 | Total control; far more code than Recharts for the forms we need, and the chart rules are the standard either way |
| Chart.js or ECharts | Canvas-based, so charts stop being inspectable DOM and stop inheriting tokens cleanly |
| Inventing a palette to taste | The specific failure the method exists to prevent. Colourblind-safety and contrast are computable, so they are computed |
| Red expenses, green income | Conventional in finance apps and wrong here: it marks ordinary life as failure, and it spends the status palette on something that is not a status |
| Skipping dark mode | The household reads this on phones at night. A flipped light theme looks broken; a designed one does not |

## Consequences

**Good:**
- Screens look like one app without anyone maintaining a style guide by hand.
- Both hands keep working: the agent writes components, an admin restyles them
  in Onlook, because the classes are right there in the markup.
- Chart decisions are made by a procedure with checks, so they are right by
  construction rather than by argument.
- Accessibility and colourblind-safety are properties of the system, not of
  whoever built the screen.

**Bad, and the price we accept:**
- shadcn components are copied, not depended on, so **upstream fixes do not
  arrive automatically** — each component is ours to maintain once pasted.
- Tailwind classes in the markup make JSX noisy to read; this is the direct cost
  of Onlook's editability.
- The chart rules will sometimes forbid the obvious thing — a dual axis, a
  fourth colour in a scatter — and the alternative will take longer.
- The relief rule on three light-mode slots means some charts must carry labels
  or a table view they would otherwise skip.

**What becomes harder to change later:** tokens spread through every screen, so
renaming a role is a sweep. Using roles rather than hex is what makes *revaluing*
one free, which is the change that actually happens.
