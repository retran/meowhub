---
spec: 0006
created: 2026-09-13
updated: 2026-09-13
---

# 0006 — Implementation plan

> Answers "how". If the plan contradicts the spec, the spec gets fixed first.

## Approach

The screens are already designed — question, data, form, layout, states, both
languages — in [docs/design/screens.md](../../docs/design/screens.md). This plan
builds what that document specifies and does not redesign it. What is left is
mechanism: a build, a client, a component layer, a keyboard model, and the tests
that close the criteria.

Build order follows R22, and each step is verifiable on its own:

1. **The shell before any screen**: the Next.js static export, the Caddy route
   that serves it behind the boundary, the PostgREST client against relative
   paths, the token layer that does not exist because the proxy supplies it, and
   the catalogue-backed i18n. Nothing renders a figure yet, and A16 is closable
   at this point.
2. **The design system**: ADR 0022's tokens as CSS custom properties, the four
   extra neutrals `screens.md` declares, shadcn components copied in as source,
   Recharts wrapped once. Dark is its own token column, never an inversion.
3. **The keyboard model, with the first desktop screen and not after it**
   (ADR 0037): a command registry, a focus model, the palette, the `?` map.
   Retrofitting a focus model onto built screens is a rewrite, so the registry
   exists before the second screen does.
4. **The screens in R22's order**: home, categories with the trend, merchants,
   members — phone and desktop layouts from one breakpoint, each screen's states
   built as a set rather than left for later.
5. **The confirmation queue**, which is the element the slice exists for: batch
   selection, one approval action, inline correction, and the keyboard path that
   makes thirty records a minute's work.
6. **Onlook's appearance pass**, last, by the admin who will live with it.

Writes are narrow and go through the same RLS every other caller obeys: no
capture affordance, ever (R21, A19), and a member is offered only what they may
change rather than refused after the tap.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Next.js static export served by Caddy from a volume the build writes | No application server, nothing to hold state, the proxy stays the only ingress, identical locally and deployed | Client-side routing needs an explicit fallback rule; no server-side rendering ever | **chosen** — R2a says static assets behind the boundary, and this is the smallest thing that is exactly that |
| Next.js in server mode as its own container | Server components, route handlers, a place to put a BFF | A second thing holding session state, a second place authorisation could drift from RLS, and a backend ADR 0007 explicitly refused | rejected |
| A component library with themed props (MUI, Chakra) | Faster to assemble | Styling leaves the markup, which blinds Onlook — the single constraint ADR 0007 accepted to keep appearance the admins' call | rejected |
| Ship the phone layout first and add desktop later | Smaller first milestone | The keyboard model is structural (ADR 0037's own consequence section says so); bolting a focus model onto finished screens is the rewrite this ordering avoids | rejected — desktop arrives with screen 1 |
| Its own message catalogue in the app | Conventional for a frontend | Two catalogues drift, and `scripts/test-i18n.sh` already enforces parity across `i18n/*.json` for the bot. One catalogue, two consumers | rejected |
| A client-side store caching figures across screens | Feels instant | A stale figure shown as current is precisely what A12 forbids; caching is per-view with explicit revalidation instead | rejected |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `app/` | New: the Next.js application, Tailwind config, tokens, shadcn components as source, the PostgREST client, the command registry, the screens | specs 0007, 0009, 0010 each add screens to it |
| `app/docker/` | A build stage (`node`, no native install on the host) producing `app/out`, written into a named volume | none |
| `compose.yaml` | A one-shot `app-build` service in the same shape as `migrate`, and the `app_dist` volume the proxy mounts read-only | none |
| `proxy/Caddyfile` | A route serving the app to **any** signed-in member — the existing catch-all requires the `admin` group, so the app cannot live behind it — plus the SPA fallback for deep links | spec 0007 adds no route; its screens are inside the app |
| `db/migrations/` | Nothing this slice creates from scratch: the views are spec 0004's. Two small additions it does own — a member may update their own `language` and `theme` (see below), and the merchant-merge function R20 needs | spec 0007+ add their own views |
| `i18n/` | Every string the app shows: labels, empty states, errors, buttons, the shortcut map, the palette | every slice |
| `Taskfile.yml` | `task app:build`, and `test:app` wired into `task test` | — |
| `scripts/` | `test-app-journeys.sh` (Playwright, containerised), `test-app-no-capture.sh` (A19), `test-app-literals.sh` (A13a) | — |
| `docs/guides/ui-editing.md` | New: how an admin changes appearance in Onlook without touching logic | when Onlook's behaviour changes |

## Contracts and data

- **Every figure comes from a view in
  [data-model.md](../../docs/architecture/data-model.md)**, by name, and the app
  computes nothing (R5). The screens bind to: `v_account_balance`,
  `v_period_spend`, `v_unconfirmed_summary`, `v_period_reconciliation`,
  `v_category_spend`, `v_category_spend_by_month`, `v_merchant_spend`,
  `v_merchant_spend_by_month`, `v_member_spend`, `v_member_spend_by_month`,
  `v_unconfirmed`, `v_transaction_detail`, `v_transaction_search`,
  `v_liability_summary`, `v_account`, `v_category`, `v_member`. All are spec
  0004's to produce; this slice consumes them and adds none.
- **`v_unconfirmed` must carry which fields were inferred.** The queue's design
  marks inferred values because they are the only part worth a human's
  attention; without that column the screen cannot be built as designed. It is
  part of that view's signature, not a detail of this app.
- **The data path is `/rest/*`**, relative, with no `Authorization` header ever
  set by the app: Caddy's forward-auth chain adds it from the session (spec
  0002 R16a, already built and proven by `scripts/test-proxy-path.sh`). The app
  holds no token and no credential (R3, A16).
- **Two writable paths this slice needs that do not exist yet:**
  - **A member's own `language` and `theme`.** R6b/R6c and A13b/A13c require a
    member to change both, but spec 0002's `member_write` policy grants writes
    to `hh_admin` only — today the daughter cannot change her own language. A
    policy permitting `hh_member` to update exactly those two columns on exactly
    their own row, and nothing else, is part of this slice.
  - **Merchant merge** (R20, A10): a database function that repoints
    transactions and aliases and leaves every figure unchanged, callable by
    `hh_admin` alone. It is a function rather than a view write because it
    touches two tables and must be one audited unit.
- **Undo (R23, A17)** reuses spec 0003's compensating-change mechanism rather
  than inventing a second one; the app calls the same function the bot's "undo"
  calls (ADR 0036). If that function is not exposed to PostgREST by spec 0003,
  exposing it is part of this slice.
- **Tokens** are the eight neutrals in `screens.md` plus ADR 0022's validated
  palette, light and dark columns both. No hex outside that table appears in any
  screen; a screen needing a new neutral is proposing a token, which is a
  decision made in this plan rather than in a commit.

## Migration and compatibility

- Nothing existing changes shape. The app is additive: a new Caddy route, a new
  volume, a one-shot build service.
- **The Caddyfile change is the one with blast radius.** The current catch-all
  gates everything behind `require-group/admin` for n8n's editor; the app must
  be reachable by every signed-in member, so the app's route is matched before
  it and gated only by Authentik forward-auth. Getting the order wrong locks the
  daughter out of the app or exposes n8n — so the ingress boundary test gains a
  case for each.
- **Reversible**: the two migrations have `down`; removing the app is removing a
  route, a volume and a directory.
- **A session that expires while the app is open** (the spec's edge case) is a
  redirect on an XHR, which is opaque to fetch. The client detects the
  authentication redirect explicitly and sends the browser through it, returning
  to the same screen — not a silent empty list.

## Verification strategy

Figures are checked against the views by querying both and comparing, never by
reading the component. Screens are checked by driving a real browser: Playwright
in a container (nothing installed natively), at 390 px for the phone journeys
and 1440 px for the desktop and keyboard passes, against the seeded household.
Permission claims are closed at the database by impersonation, never by the
absence of a button (ADR 0015).

| Acceptance criterion | How we verify it |
|---|---|
| A1 | Playwright at 390 px: read each balance and the month's total off the home screen; assert equal to `v_account_balance` and `v_period_spend` queried directly |
| A2 | The same figures compared against spec 0004's digest output for the same period, asserted identical |
| A3 | Playwright: open a category, assert the trend renders, a legend is present at two or more series, and the table view is reachable |
| A4 | Seed an account overdrawn; assert the balance renders negative with its limit, and its computed colour is a text token, not the error status token |
| A5 | Seed a period with provisional statement lines and unconfirmed records; assert both carry their marker in the DOM, distinct from confirmed rows |
| A6 | Playwright: select ten of twelve, approve; assert exactly ten rows changed state and each audit row names the actor and route |
| A7 | Inline-edit an amount in the queue; assert the transaction changed and `audit_log` holds both states |
| A8 | Run the queue journey as `hh_member`: assert category and own-capture confirm are present and amount, date and account controls are absent from the DOM |
| A9 | pgTAP, impersonating `hh_member`: `update` of a transaction's amount fails — closed at the database, independent of A8 |
| A10 | Merge two seeded merchants through the app; assert aliases and transactions repoint and `v_category_spend` and `v_merchant_spend` totals are unchanged |
| A11 | Run every screen against an empty database and against a filtered-empty period; assert the two states render different catalogue keys |
| A12 | Stop PostgREST; assert the app shows the error state with a retry and no figure from the previous render remains on screen |
| A13 | Playwright in both languages at the longest catalogue string per label; assert no element's `scrollWidth` exceeds its `clientWidth` |
| A13a | `scripts/test-app-literals.sh`: scan the built bundle for user-visible text and assert every such string is present in `i18n/*.json`; any literal fails |
| A13b | Switch language in the app; send a capture to the bot; assert Meow's reply is in the new language — one property, checked across both surfaces |
| A13c | Device preference dark, member choice light: assert the light token column is applied; then the reverse |
| A13d | Render an amount and a date in each language; assert `1 847,20 €` against `1,847.20 €` and the matching date conventions |
| A14 | Playwright in light and dark: assert computed colours resolve to token values and that dark values come from the dark column, not from inverted light ones |
| A14a | The same journeys with the webfont request blocked; assert nothing overflows and nothing is clipped |
| A15 | `scripts/test-app-journeys.sh` in `task test` — run, not reasoned about |
| A16 | Build from a clean checkout by the documented command; assert the output is static files, and request them without a session: refused by the boundary |
| A17 | Make a correction, undo it; assert the previous state is restored by a compensating change and both appear in `audit_log` |
| A18 | Open a photo-derived transaction's detail; assert the note, the receipt and the category's origin all render, matching what `v_transaction_detail` returns |
| A18a | Read every figure on the 1440 px desktop overview, the 390 px phone home, and the bot's answer for the same period; assert all three equal |
| A18b | Keyboard-only Playwright pass: `j`/`k`, `Space`, `E` — approve a batch with no pointer event dispatched at all |
| A18c | Enumerate each desktop screen's declared keys from the `?` map and drive every one of them; assert each action fires. Enumerated per screen, not sampled |
| A18d | Open the palette as `hh_member`: assert no admin-only entry is listed; then call the same action against PostgREST directly and assert it fails at the database |
| A18e | After a keystroke approval, assert focus is on the next row and its focus ring is rendered |
| A18f | At 390 px, assert the palette cannot be opened and no shortcut hint exists in the DOM |
| A19 | `scripts/test-app-no-capture.sh`: assert no route, form or control in the built bundle creates a transaction — a permanent property, asserted rather than reviewed |
| A20 | Delete a transaction as an admin with confirmation; assert balances change accordingly and the deletion with its final state is in `audit_log` |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Playwright cannot complete a real sign-in because of Authentik's documented non-standard-port redirect bug (`docs/guides/local-development.md`) | high | Run the journeys from a container inside the proxy's own network namespace against port 443, where the bug does not arise — the same "borrow the target's namespace" trick the existing scripts use. `AUTHENTIK_APP_EXTERNAL_HOST` must match that host for the run |
| The app's Caddy route is ordered wrong and either exposes n8n or locks non-admin members out | medium | Both cases become assertions in the ingress boundary test, not review items |
| Spec 0004's views do not yet carry what a screen needs — inferred-field markers on `v_unconfirmed`, the unconfirmed share on every total | medium | Named as contracts above, so the gap surfaces as a failing build against a view signature rather than as a screen quietly showing less |
| `v_transaction_detail`'s "where the category came from" depends on provenance columns spec 0003 must write | medium | A18 fails loudly if provenance is absent; nothing is invented in the app to paper over it |
| The keyboard model grows past what ADR 0007 called a thin app | high, and accepted | ADR 0037 already priced this. Kept small by one registry, one focus model, no configurability |
| Onlook patches produce noisy or incorrect diffs | medium | Whatever it emits is a commit like any other — reviewed, and the journeys re-run before it lands. Drift detection (ADR 0010) does not apply: the app *is* the repository, so there is no exported bundle to reconcile |
| Static export plus client routing breaks deep links | low | The SPA fallback is part of the Caddy route and a journey navigates directly to a nested URL |

## ADRs required

None. ADR 0007 fixes the framework, 0022 the design system, 0037 the keyboard
model, 0014 the data path and 0016 the permissions — this slice builds what they
already decided. The two database additions above (a member's own language and
theme; the merchant-merge function) are feature-local decisions and stay here.
