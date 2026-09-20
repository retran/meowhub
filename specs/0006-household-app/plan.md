---
spec: 0006
created: 2026-09-13
updated: 2026-09-13
---

# 0006 - Implementation plan

> This plan says how we build the slice. When the plan and the spec disagree, we
> fix the spec first and then the plan.

## Approach

[docs/design/screens.md](../../docs/design/screens.md) already designs the
screens - question, data, form, layout, states, both languages - so this plan
builds what that document specifies and doesn't redesign it. What's left is a
build, a client, a component layer, a keyboard model, and the tests that close
the criteria.

We build in R22's order, and each step can be verified on its own:

1. The shell, before any screen: the Next.js static export, the Caddy route that
   serves it behind the boundary, the PostgREST client against relative paths,
   the token layer that doesn't exist because the proxy supplies the header, and
   the catalogue-backed i18n. Nothing renders a figure yet, and we can close A16
   at this point.
2. The design system: ADR 0022's tokens as CSS custom properties, the four extra
   neutrals `screens.md` declares, shadcn components copied in as source, and
   Recharts wrapped once. Dark gets its own token column and is never an
   inversion.
3. The keyboard model, built together with the first desktop screen (ADR 0037):
   a command registry, a focus model, the palette, and the `?` map. Retrofitting
   a focus model onto built screens is a rewrite, so the registry exists before
   the second screen does.
4. The screens in R22's order: home, categories with the trend, merchants, and
   members, with phone and desktop layouts from one breakpoint and every state
   of a screen built in the same pass as the screen.
5. The confirmation queue, which is what the slice exists for: batch selection,
   one approval action, inline correction, and the keyboard path that turns
   thirty records into a minute's work.
6. Onlook's appearance pass, last, done by the admin who will live with it.

Writes stay narrow and go through the same row-level security every other caller
obeys. The app never offers a way to capture an expense (R21, A19), and it shows
a member only the controls they can use, so nothing is refused after the tap.

## Alternatives considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Next.js static export served by Caddy from a volume the build writes | No application server, nothing to hold state, the proxy stays the only ingress, identical locally and deployed | Client-side routing needs an explicit fallback rule; no server-side rendering ever | **chosen** - R2a asks for static assets behind the boundary, and this is the smallest thing that is exactly that |
| Next.js in server mode as its own container | Server components, route handlers, a place to put a BFF | A second thing holding session state, a second place authorisation could drift from RLS, and a backend ADR 0007 refused outright | rejected |
| A component library with themed props (MUI, Chakra) | Faster to assemble | Styling leaves the markup, which blinds Onlook - the one constraint ADR 0007 accepted so that appearance stays the admins' call | rejected |
| Ship the phone layout first and add desktop later | Smaller first milestone | The keyboard model is structural, as ADR 0037's own consequence section says, and bolting a focus model onto finished screens is the rewrite this ordering avoids | rejected - desktop arrives with screen 1 |
| Its own message catalogue in the app | Conventional for a frontend | Two catalogues drift, and `scripts/test-i18n.sh` already enforces parity across `i18n/*.json` for the bot. One catalogue, two consumers | rejected |
| A client-side store caching figures across screens | Feels instant | Showing a stale figure as current is what A12 forbids, so caching is per-view with explicit revalidation | rejected |

## Affected areas

| Area | This slice | Extended by |
|---|---|---|
| `app/` | New: the Next.js application, Tailwind config, tokens, shadcn components as source, the PostgREST client, the command registry, the screens | specs 0007, 0009, 0010 each add screens to it |
| `app/docker/` | A build stage (`node`, no native install on the host) producing `app/out`, written into a named volume | none |
| `compose.yaml` | A one-shot `app-build` service in the same shape as `migrate`, and the `app_dist` volume the proxy mounts read-only | none |
| `proxy/Caddyfile` | A route serving the app to **any** signed-in member - the existing catch-all requires the `admin` group, so the app cannot live behind it - plus the SPA fallback for deep links | spec 0007 adds no route; its screens are inside the app |
| `db/migrations/` | Nothing this slice creates from scratch: the views are spec 0004's. Two small additions it does own - a member updating their own `language` and `theme` (see below), and the merchant-merge function R20 needs | spec 0007+ add their own views |
| `i18n/` | Every string the app shows: labels, empty states, errors, buttons, the shortcut map, the palette | every slice |
| `Taskfile.yml` | `task app:build`, and `test:app` wired into `task test` | - |
| `scripts/` | `test-app-journeys.sh` (Playwright, containerised), `test-app-no-capture.sh` (A19), `test-app-literals.sh` (A13a) | - |
| `docs/guides/ui-editing.md` | New: how an admin changes appearance in Onlook without touching logic | when Onlook's behaviour changes |

## Contracts and data

This section names the views the screens bind to and the three write paths the
slice needs, so that a missing column fails the build instead of quietly
shrinking a screen.

- Every figure comes by name from a view in
  [data-model.md](../../docs/architecture/data-model.md), and the app computes
  nothing (R5). The screens bind to `v_account_balance`, `v_period_spend`,
  `v_unconfirmed_summary`, `v_period_reconciliation`, `v_category_spend`,
  `v_category_spend_by_month`, `v_merchant_spend`, `v_merchant_spend_by_month`,
  `v_member_spend`, `v_member_spend_by_month`, `v_unconfirmed`,
  `v_transaction_detail`, `v_transaction_search`, `v_liability_summary`,
  `v_account`, `v_category`, and `v_member`. Spec 0004 produces all of them;
  this slice consumes them and adds none.
- `v_unconfirmed` has to carry which fields were inferred. The queue's design
  marks inferred values because they are the only part that needs a person's
  attention, so without that column we can't build the screen as designed. The
  column belongs to that view's signature rather than to this app.
- The data path is `/rest/*`, relative, and the app never sets an
  `Authorization` header: Caddy's forward-auth chain adds it from the session
  (spec 0002 R16a), which is already built and proven by
  `scripts/test-proxy-path.sh`. The app holds no token and no credential (R3,
  A16).
- Two writable paths this slice needs don't exist yet:
  - A member's own `language` and `theme`. R6b, R6c, A13b, and A13c require a
    member to change both, but spec 0002's `member_write` policy grants writes to
    `hh_admin` only, so today the daughter cannot change her own language. This
    slice adds a policy that lets `hh_member` update exactly those two columns on
    exactly their own row, and nothing else.
  - Merchant merge (R20, A10): a database function that repoints transactions and
    aliases and leaves every figure unchanged, callable by `hh_admin` alone. We
    make it a function rather than a view write because it touches two tables and
    has to be one audited unit.
- Undo (R23, A17) reuses spec 0003's compensating-change mechanism, so the app
  calls the same function the bot's "undo" calls
  (ADR 0036). If spec 0003 doesn't expose that function to PostgREST, this slice
  exposes it.
- The tokens are the eight neutrals in `screens.md` plus ADR 0022's validated
  palette, in both the light and the dark column. No hex outside that table
  appears in any screen, and a screen that needs a new neutral is proposing a
  token, which we agree here before the screen is built.

## Migration and compatibility

The app is additive: a new Caddy route, a new volume, and a one-shot build
service, with nothing existing changing shape.

- The Caddyfile change is the one that can break other things. The current
  catch-all gates everything behind `require-group/admin` for n8n's editor, and
  the app has to be reachable by every signed-in member, so we match the app's
  route before the catch-all and gate it only by Authentik forward-auth. Getting
  the order wrong locks the daughter out of the app or exposes n8n, so the
  ingress boundary test gains a case for each.
- Both migrations have a `down`, and removing the app means removing a route, a
  volume, and a directory.
- A session that expires while the app is open - the spec's edge case - arrives
  as a redirect on an XHR, which fetch cannot see. The client detects the
  authentication redirect explicitly and sends the browser through it, returning
  the member to the same screen afterwards. Without that, the screen would show
  an empty list, which reads as a household with nothing recorded.

## Verification strategy

We check figures against the views by querying both and comparing, never by
reading the component. We check screens by driving a real browser: Playwright in
a container, with nothing installed natively, at 390 px for the phone journeys
and 1440 px for the desktop and keyboard passes, against the seeded household.
We close every permission claim at the database by impersonation rather than by
the absence of a button (ADR 0015).

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
| A9 | pgTAP, impersonating `hh_member`: `update` of a transaction's amount fails - closed at the database, independent of A8 |
| A10 | Merge two seeded merchants through the app; assert aliases and transactions repoint and `v_category_spend` and `v_merchant_spend` totals are unchanged |
| A11 | Run every screen against an empty database and against a filtered-empty period; assert the two states render different catalogue keys |
| A12 | Stop PostgREST; assert the app shows the error state with a retry and no figure from the previous render remains on screen |
| A13 | Playwright in both languages at the longest catalogue string per label; assert no element's `scrollWidth` exceeds its `clientWidth` |
| A13a | `scripts/test-app-literals.sh`: scan the built bundle for user-visible text and assert every such string is present in `i18n/*.json`; any literal fails |
| A13b | Switch language in the app; send a capture to the bot; assert Meow's reply is in the new language - one property, checked across both surfaces |
| A13c | Device preference dark, member choice light: assert the light token column is applied; then the reverse |
| A13d | Render an amount and a date in each language; assert `1 847,20 €` against `1,847.20 €` and the matching date conventions |
| A14 | Playwright in light and dark: assert computed colours resolve to token values and that dark values come from the dark column, not from inverted light ones |
| A14a | The same journeys with the webfont request blocked; assert nothing overflows and nothing is clipped |
| A15 | `scripts/test-app-journeys.sh` in `task test` - run, not reasoned about |
| A16 | Build from a clean checkout by the documented command; assert the output is static files, and request them without a session: refused by the boundary |
| A17 | Make a correction, undo it; assert the previous state is restored by a compensating change and both appear in `audit_log` |
| A18 | Open a photo-derived transaction's detail; assert the note, the receipt and the category's origin all render, matching what `v_transaction_detail` returns |
| A18a | Read every figure on the 1440 px desktop overview, the 390 px phone home, and the bot's answer for the same period; assert all three equal |
| A18b | Keyboard-only Playwright pass: `j`/`k`, `Space`, `E` - approve a batch with no pointer event dispatched at all |
| A18c | Enumerate each desktop screen's declared keys from the `?` map and drive every one of them; assert each action fires. Enumerated per screen, not sampled |
| A18d | Open the palette as `hh_member`: assert no admin-only entry is listed; then call the same action against PostgREST directly and assert it fails at the database |
| A18e | After a keystroke approval, assert focus is on the next row and its focus ring is rendered |
| A18f | At 390 px, assert the palette cannot be opened and no shortcut hint exists in the DOM |
| A19 | `scripts/test-app-no-capture.sh`: assert no route, form or control in the built bundle creates a transaction - a permanent property, asserted rather than reviewed |
| A20 | Delete a transaction as an admin with confirmation; assert balances change accordingly and the deletion with its final state is in `audit_log` |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Playwright cannot complete a real sign-in because of Authentik's documented non-standard-port redirect bug (`docs/guides/local-development.md`) | high | Run the journeys from a container inside the proxy's own network namespace against port 443, where the bug doesn't arise - the same "borrow the target's namespace" trick the existing scripts use. `AUTHENTIK_APP_EXTERNAL_HOST` must match that host for the run |
| The app's Caddy route is ordered wrong and either exposes n8n or locks non-admin members out | medium | Both cases become assertions in the ingress boundary test rather than review items |
| Spec 0004's views don't yet carry what a screen needs - inferred-field markers on `v_unconfirmed`, the unconfirmed share on every total | medium | The contracts above name them, so a gap surfaces as a failing build against a view signature rather than as a screen quietly showing less |
| `v_transaction_detail`'s "where the category came from" depends on provenance columns spec 0003 must write | medium | A18 fails loudly when provenance is absent, and the app invents nothing to paper over it |
| The keyboard model grows past what ADR 0007 called a thin app | high, and accepted | ADR 0037 already priced this, and one registry, one focus model and no configurability keep it small |
| Onlook patches produce noisy or incorrect diffs | medium | Whatever it emits is a commit like any other: we review it and re-run the journeys before it lands. Drift detection (ADR 0010) doesn't apply, because the app lives in the repository and has no exported bundle to reconcile |
| Static export plus client routing breaks deep links | low | The SPA fallback is part of the Caddy route and a journey navigates directly to a nested URL |

## ADRs required

None. ADR 0007 fixes the framework, 0022 the design system, 0037 the keyboard
model, 0014 the data path, and 0016 the permissions, so this slice builds what we
already decided. The two database additions above - a member's own language and
theme, and the merchant-merge function - are feature-local decisions and stay in
this plan.
