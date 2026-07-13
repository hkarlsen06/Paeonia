# Paeonia Onboarding Plan

Plan date: 2026-07-01

This is the agreed plan for Paeonia's first-run experience, split into pre-auth (the hook) and post-auth (setup + activation). It captures the current baseline as verified in code, the locked product decisions, the target flow for both partners, and the implementation slices in build order.

The pre-auth carousel, first-class invite-code entry, anniversary refactor, paywall reframe, and permission priming are implemented. The optional waiting-room gift remains a fast-follow, not an MVP blocker. `docs/implementation-map.md` is the source of truth for the files that own landed behavior.

## Guiding Insight

Paeonia's value is two-player. Nothing pays off with one person: a daily question needs a reply, a widget drawing needs a home screen to land on, a countdown needs someone to count toward. Two consequences drive every decision below:

- **The real activation event is "both partners paired + first shared exchange."** Not "signed in", not "subscribed". Everything in onboarding is judged by whether it gets the couple to that moment faster.
- **The #1 failure mode for couple apps is one partner using it alone.** Partner activation is the retention metric, and users judge setup against a "both of us linked in under five minutes" bar.

Supporting research is summarized at the end.

## Current Baseline (verified in code)

Cold-launch intro → `SignInView` (single screen) → `AuthOnboardingView` (name + optional photo) → paywall at `limitedAuthenticated` (**before pairing**) → invite/join → `PairingCelebrationView` → `MainTabView`.

- Access states live in `ios/PaeoniaApp/Services/Access/AccessRoute.swift` (`AccessRouteResolver`). The paywall shows at `.limitedAuthenticated` and `.pairedPaywalled`.
- The paywall already sells a **14-day free trial** (introductory offer live in App Store Connect) and embeds invite-code entry (`ios/PaeoniaApp/Features/Paywall/Components/PaywallInviteCodeView.swift`), so the joining partner pays nothing — one `coupleEntitlement` covers the couple.
- Post-auth setup collects only display name (single word, prefilled from Apple/Google) plus an optional photo (`ios/PaeoniaApp/Features/Auth/AuthBaselineViews.swift`, `AuthOnboardingView`). Timezone is captured silently.
- **Relationship dates are contextual and truthful.** Ordinary invite acceptance leaves `couples.started_on` unset. The Us-tab milestone tile shows an honest setup state, either entitled partner can set or edit the date, and the local-first queue preserves the newest choice until both clients refresh.
- **Permissions are contextual asks.** Push keeps its post-pairing timing, but `RootView` first presents a persisted one-benefit primer and requests the iOS permission only after an explicit continue. Location remains lazy at the map surface, where the empty state explains latest-location-only, foreground-only, no-history behavior before the system request.

## Pre-Auth vs Post-Auth

These are two different jobs and should feel different.

| | Pre-auth onboarding | Post-auth onboarding |
|---|---|---|
| Job | Hook — sell the feeling, earn the sign-in | Setup + activation — collect what the app needs, get them paired |
| Audience | Everyone who opens the app | Only people who committed to sign in |
| Tone | Emotional, cinematic, benefit-led | Warm but efficient; every screen earns its place |
| Data | Collect nothing that needs an account | Name, photo, the pairing link |
| Success metric | Sign-in rate | Paired-couple rate + first-exchange rate |

## Locked Decisions

1. **Paywall stays trial-before-pairing.** The 14-day trial mechanism already exists — this plan does not add a trial. The only changes are copy and an optional gift:
   - **Copy reframe** — center the paywall on "start your free trial and open your shared space with {partner}" rather than a feature/price gate. Same offer; the payment gains an emotional, concrete purpose.
   - **Waiting-room first gift (optional, fast-follow)** — after the inviter starts the trial and sends the invite, let them write the first note / draw the first doodle / answer the first question while they wait, so the partner arrives to something waiting for them. Highest-leverage lever against the "one partner alone" failure. Not a v1 blocker.
2. **Pre-auth hook: 3 shared-artifact screens** (swipeable, skippable) before the sign-in wall — daily-question reveal, home-screen doodle, countdown. One benefit per screen. Also surface a first-class "Joining a partner? Enter your code" path so a texted-a-code joiner never lands on the paywall by accident.
3. **Anniversary is not collected during onboarding.** Make `couples.started_on` nullable; stop hard-coding it at pairing. Add a setup state to the Us-tab milestone card that asks the couple to set the day they got together, written by either partner and editable later.
4. **Permissions get priming.** Push keeps its `.paired` timing but gains a one-benefit primer with a "Not now"; location stays lazy at the map surface with one line of context. Neither is asked during onboarding.

## Target Flow

See the recommended-flow diagram shared alongside this plan for the visual. In words:

**Pre-auth (all users):** 3 shared-artifact screens → sign in (Apple/Google), with "I have an invite code" surfaced early.

**Post-auth — Partner A (inviter):** name & photo → trial paywall (reframed) → invite partner → *(optional: leave the first gift while waiting)*.

**Post-auth — Partner B (joiner):** tap invite link → name & photo → Join {A} (covered by A's trial; no paywall).

**Converge:** paired → `PairingCelebrationView` → primed push ask → first shared question on Home.

What is intentionally gone: no anniversary step in setup, keeping time-to-pairing minimal.

## Data Collection Matrix

Collect each item at the latest moment it is actually needed, tied to the benefit it unlocks. Never front-load a form.

| Data / permission | Required | Collect when | Why there |
|---|---|---|---|
| Identity (Apple/Google) | Yes | The auth wall, after the hook | Nothing works without it; earn it first |
| Display name (single word) | Yes | First post-auth step, prefilled | Partner sees it at celebration; ~2s |
| Timezone | Yes | Silent, at onboarding | Couple-day rituals need it; never ask |
| Profile photo | Optional | Same setup step, skippable | Warms celebration + paired header |
| The pairing link | Yes | After paywall (A); via link (B) | The activation gate |
| Anniversary (`started_on`) | Deferred | Us-tab milestone setup card | Makes the countdown truthful; contextual moment |
| Push permission | Core loop | Primed, at/just-after pairing | Tie to "when {partner} draws or replies" |
| Location permission | Optional | Lazy + primed, at the map surface | Both partners must opt in |
| Photo library | Optional | Lazy, at first save | Already correct |

## Implementation Slices (build order)

### 1. Anniversary refactor (start here — most self-contained)

Turns a faked value into an honest, contextual moment and unblocks accurate countdowns.

- [x] New migration: make `couples.started_on` nullable. Follow `docs/phase-3-migration-checklist.md`; create with `supabase migration new <name>`.
- [x] Add a `set_couple_started_on` public RPC wrapper over an `internal.*` implementation. It **must** be `security definer` with a pinned `search_path` (authenticated has no USAGE on `internal` — see AGENTS.md and `docs/phase-3-migration-checklist.md`). Writable by either partner in the couple; authorization enforced inside the internal function via `auth.uid()` / entitled-couple checks.
- [x] Pairing: drop the hard-coded `PairingStartDate(date: Date())` in `ios/PaeoniaApp/Features/Paywall/Offer/PaywallViewModel.swift`; make `PairingStartDate` / the `p_started_on` param optional through `PairingService.acceptInvite` and `SupabasePairingGateway` so accept no longer sets a date.
- [x] Us tab: give `MilestoneCountdownCard` a setup state when `startedOn == nil` — a calm "Set the day you got together" prompt with a date picker — instead of hiding or faking. The card already takes `startedOn: String?`, so this is additive (`ios/PaeoniaApp/Features/Countdown/Components/MilestoneCountdownCard.swift`).
- [x] Wire the write through local-first sync so both partners see the update, and keep it editable later.
- [x] Tests: milestone card nil → setup → set transition; RPC scoping/authorization; sync propagation to the partner; `RelationshipMilestoneCalculator` with a set date (existing coverage in `ios/PaeoniaAppTests/RelationshipMilestoneTests.swift`).

### 2. Pre-auth hook + first-class code entry

- [x] Add a 3-screen, swipeable, skippable value sequence before `SignInView` (daily-question reveal, home-screen doodle, countdown). Keep it copy-light and honor Reduce Motion, matching the launch-intro tone in `ios/PaeoniaApp/Features/Auth/`.
- [x] Surface "Joining a partner? Enter your code" as a first-class path at/near sign-in so joiners never route through the paywall to find the code field.
- [x] Respect `PresentationReadinessProviding` for any launch-adjacent screen; do not dismiss the launch surface until the first surface is stable (AGENTS.md → Stable Presentation Readiness).
- [x] Localize all copy with generated `LocalizedStringResource` symbols; add entries via `./scripts/xcstrings-set` (English + Norwegian Bokmal + translator comment).

### 3. Paywall copy reframe

- [x] Reframe paywall copy around "open your shared space with {partner}" using the existing trial offer; no StoreKit/offer changes. Update `PaywallPresentation` / `PaywallAudience` copy paths (`ios/PaeoniaApp/Features/Paywall/`).
- [x] Keep copy understandable to an ordinary 16-year-old; no internal terms (AGENTS.md → Product Copy Clarity).

### 4. Push and location priming

- [x] Add a priming screen before the system push dialog, with one concrete benefit ("When {partner} draws on your home screen or answers today's question, we'll let you know") and a "Not now". Keep the `.paired` trigger in `ios/PaeoniaApp/App/RootView.swift`; prime before `PushAuthorizationService.requestAuthorizationIfNeeded()`.
- [x] Add the same one-line context before the location system dialog at the map surface. Do not ask for location during onboarding.

### 5. Waiting-room first gift (only if wanted in v1)

- [ ] After invite send, let the inviter create the first note / drawing / answer while waiting, delivered to the partner on join. Reuse existing Daily Challenge / widget drawing composers rather than new surfaces. Confirm scope before building — this is the one item that is optional for v1.

## Related Docs

- `docs/implementation-map.md` — feature ownership (launch/auth/pairing/paywall/countdown).
- `docs/phase-3-data-contract.md` — product/data-model decisions before schema work.
- `docs/phase-3-migration-checklist.md` — migration order, RLS helpers, RPC grants.
- `docs/phase-2-design/07-voice-and-copy.md` — copy tone for all new strings.
- `docs/ux-friction-report.md` — current UX risks in auth/onboarding/paywall.
- `AGENTS.md` — RPC security-definer rule, presentation readiness, localization, copy clarity.

## Research Basis

- Churn happens before the paywall, not at it; deliver a value moment first — [Airbridge](https://www.airbridge.io/blog/subscription-app-onboarding), [AppAgent](https://appagent.com/blog/mobile-app-onboarding-5-paywall-optimization-strategies/).
- Couple apps live or die on partner activation; "both linked in under five minutes" is the bar — [connectedcouples](https://www.connectedcouples.app/blog/best-couples-apps-2026), [Habi](https://habi.app/insights/best-couple-apps/).
- Reduce friction, one benefit per screen, delay asks to a value moment — [Appcues](https://www.appcues.com/blog/mobile-onboarding), [Plotline](https://www.plotline.so/blog/mobile-app-onboarding-examples).
- Permission priming roughly doubles opt-in vs a cold ask — [Appcues](https://www.appcues.com/blog/mobile-permission-priming), [Plotline](https://www.plotline.so/blog/how-to-improve-push-notification-opt-in-rates).
- Partner-invite patterns in comparable couple apps — [Cupla](https://help.cupla.app/article/9-how-do-i-invite-my-partner).
