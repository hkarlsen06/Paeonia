# Paeonia UI Friction Report

Source review date: 2026-06-29

## Scope

This audit reviewed the current SwiftUI app surfaces and the marketing site source. It focused on consumer UX friction: confusing wording, misleading placement, unfinished entry points, destructive-flow clarity, privacy-sensitive copy, and small interaction choices that can cause hesitation.

No simulator, browser pass, build, or tests were run. Findings are based on source inspection only.

Reviewed surfaces:

- iOS launch, auth, onboarding, pairing, paywall, home tabs, Daily Challenge, widget drawing, location, settings, and shared UI components
- Marketing landing, join fallback, legal/support shell, and English/Norwegian dictionaries

## Overall Assessment

Paeonia has a strong product foundation: calm native layout, good use of stable launch readiness, a clear local-first direction, and several thoughtful interaction details. The biggest satisfaction risk is not visual polish. It is trust leakage from pre-release copy and unfinished surfaces that are still reachable.

The highest priority is to remove or rewrite any UI that tells a real user they are in a test build, a placeholder, or a future feature. Paeonia handles private relationship content; copy must be precise when account deletion, relationship access, subscription, invite pairing, and location sharing are involved.

## What Is Working

- The app already avoids many noisy social patterns. The core language uses "partner", "private space", "questions", "drawing", and "location" instead of dating-app or public-feed terms.
- Daily Challenge has good local-first reassurance: "Saved on this phone. We'll send it when you're online." This matches the product bar and should be reused in other save failures.
- The launch/loading pattern is intentionally blank and stable, which matches the design docs and avoids flickering explanatory copy.
- Top-level recoverable errors are centralized through the shared banner instead of scattered system alerts.
- The widget drawing and Daily Challenge flows have real interaction depth, not just static mockups.

## Priority Findings

### P0: Delete-account copy still sounds like a test build

Evidence:

- `ios/PaeoniaApp/Features/Paywall/PaywallFooterActionsView.swift` exposes `Delete account` in the paywall footer.
- `ios/PaeoniaApp/Features/Paywall/PaywallView.swift` and `ios/PaeoniaApp/Features/Auth/AuthBaselineViews.swift` both show the delete confirmation alert.
- `ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings` says: "This removes the test account from this phone."

Why it matters:

This is a destructive privacy flow. "Test account" makes the product feel unsafe and unfinished. "From this phone" also understates the consequence if deletion removes server account data, relationship membership, or shared access. Users need to know what is deleted, what happens to the relationship, and whether it can be undone.

Fix:

- Replace the confirmation message with real consequence copy before any external use.
- State whether the account is deleted from Paeonia, whether the user leaves the relationship, what happens to shared content, and whether the action can be undone.
- Keep the centered alert pattern, but make the destructive action label specific.

Suggested copy:

| Current | Replace with |
| --- | --- |
| Delete this account? | Delete your account? |
| This removes the test account from this phone. | This deletes your Paeonia account and removes you from this relationship. This cannot be undone. |
| Delete account | Delete account |
| Keep account | Keep account |

Acceptance criteria:

- No production string contains "test account" unless it is behind a debug-only test-account flow.
- The Norwegian string is rewritten with the same real consequence.
- The delete failure banner says what happened and what the user can do next.

### P1: Unfinished features are visible as reachable UI

Evidence:

- `ios/PaeoniaApp/App/MainTab.swift` includes a `Memories` tab.
- `ios/PaeoniaApp/App/MainTabView.swift` routes `.memories` to `placeholderTab`.
- `mainTab.placeholder.message` says: "We're still building this part. Check back soon."
- `ios/PaeoniaApp/Features/Countdown/MilestoneCountdownCard.swift` renders hardcoded placeholder values: "Your 6-month milestone", `12`, and "Saturday, 8 July".
- `AuthUnavailableRouteView` uses "This part is not ready yet"; `RootView` can route `relationshipEndedNotice` into that fallback.
- `AGENTS.md` explicitly says unfinished features should not be wired as placeholders unless the developer confirms that interim state.

Why it matters:

Consumer apps lose trust quickly when navigation leads to "not ready" screens or fake dates. In Paeonia, fake relationship milestones are especially risky because dates and memories are emotionally loaded. A hardcoded countdown can make users think the app is wrong about their relationship.

Fix:

- Remove the `Memories` tab until there is a real memory timeline or a functional empty state with a create action.
- Remove the countdown tile until milestone math is wired, or compute it from the real relationship start date.
- If the start date is missing, show an honest setup state, not a fake date.
- Replace `AuthUnavailableRouteView` for `relationshipEndedNotice` with a real relationship-ended state.
- Delete or isolate placeholder root strings that are no longer reachable.

Suggested copy if a real empty state exists:

| Context | Copy |
| --- | --- |
| Memories empty state | No memories yet. Save a small moment from today. |
| Missing milestone date | Add your relationship date to see your next milestone. |
| Relationship ended | You no longer have access to this relationship. |

### P1: Partner-answer reveal states depend too much on icons

Evidence:

- `DailyQuestionStatusView` uses the same title, `dailyChallenge.partnerHidden` ("Your partner answered"), whether the partner answer is hidden or viewable. Only the icon changes between lock and heart.
- `DailyPartnerWaitingNote` says: "Answer this question to see what your partner said."
- `DailyChallengeReadCard` uses `Answer to see their reply` or `Finish your questions first`.

Why it matters:

The rule is subtle: partner replies exist, but they are hidden until the user answers. A lock icon alone is not enough. Users may think the partner answer should already be visible, or that the app failed to load it. This can create unnecessary frustration at the main emotional payoff moment.

Fix:

- Use different status text for locked versus revealed answers.
- Add one short explanatory line at the top of the partner section when locked cards exist.
- Keep the CTA specific and consistent: avoid switching between "answers", "reply", and "said" for the same concept.

Suggested copy:

| Current | Replace with |
| --- | --- |
| Your partner answered | Your partner's answer is waiting |
| Answer this question to see what your partner said. | Answer this question to unlock their answer. |
| Answer to see their reply | Answer to unlock it |
| Finish your questions first | Finish your three first |
| Answer to see your partner's answers | Answer partner questions |

### P1: Paywall invite entry competes with subscription purchase

Evidence:

- `PaywallScrollCue` says "Invited? Enter key here".
- `PaywallInviteCodeView` says "Enter the 6-character code your partner shared with you."
- The bottom CTA changes from purchase to "Join your partner" while invite mode is open.
- The subscription CTA can be `Continue`, which is vague for a paid step.
- Norwegian paywall copy has at least one typo: "Start min gratise prøveperiode".

Why it matters:

Invited users are in a different mental state from purchasers. They are trying to join a partner, not evaluate a subscription. Hiding invite entry behind a scroll cue and using both "key" and "code" adds friction. On a paywall, "Continue" is also too vague because users need to know whether the next step is App Store confirmation, a free trial, or payment.

Fix:

- Make "I have an invite code" a persistent secondary action near the bottom CTA when invite entry is allowed.
- Use "code" everywhere, not "key".
- Put the join action inside the invite panel or make the bottom CTA visually and textually belong to the invite panel.
- Rename paid CTAs to state the next step.
- Audit Norwegian paywall strings before App Store review.

Suggested copy:

| Current | Replace with |
| --- | --- |
| Invited? Enter key here | Have an invite code? |
| Continue | Continue to App Store |
| Start in 2 taps, cancel anytime. | The App Store confirms before you pay. Cancel anytime. |
| Start min gratise prøveperiode | Start min gratis prøveperiode |
| Skriv inn den 6-tegns koden partneren din delte med deg. | Skriv inn koden på 6 tegn som partneren din delte med deg. |

### P2: The widget drawing screen does not say what saving does

Evidence:

- `WidgetDrawingView` title is "Drawing".
- Primary action is "Save"; success state is "Saved".
- The home tile says "Draw something", and the history button says "Drawing history".
- Save failure says: "Something went wrong while saving. Please try again."

Why it matters:

The screen is a shared widget authoring tool, but the main surface does not make the outcome explicit. A user should not have to infer whether Save updates their own phone, their partner's widget, or a private draft. Since the feature is intimate and local-first, save failure should reassure users that the drawing is still safe.

Fix:

- Rename the screen and primary action around the outcome.
- Add a one-line empty/new-state hint near the canvas only when it helps first use.
- Reuse local-first error language when save fails.
- Keep Clear visually secondary and destructive-confirmed.

Suggested copy:

| Current | Replace with |
| --- | --- |
| Drawing | Shared widget |
| Save | Send to widget |
| Saved | Sent |
| Something went wrong while saving. Please try again. | Your drawing is still here. Try sending again. |

### P2: Onboarding name validation explains the rule after the user breaks it

Evidence:

- `AuthDisplayNamePolicy.validatedSingleName` rejects names with more than one word.
- `AuthOnboardingView` disables "Finish setup" until the value is a single word.
- The hint "Use one word only." appears only after multiple words are entered.

Why it matters:

"First name or nickname" is clear, but not enough to explain why a common name like "Mary Jane" or "Anna Sofia" fails. Disabled buttons without a visible reason feel broken, especially in first-run onboarding.

Fix:

- Decide whether Paeonia truly requires one word. If not, allow multiword display names and use a shortened first-name fallback where needed.
- If one word is required, explain it before the user hits the disabled button.
- Make the hint warmer and more user-centered.

Suggested copy:

| Current | Replace with |
| --- | --- |
| First name or nickname | Name your partner will see |
| Use one word only. | Use a short name, like Mina or Eli. |
| Finish setup | Continue |

### P2: Location sharing copy needs more privacy reassurance

Evidence:

- Settings subtitle: "Your partner can see your latest location while sharing is on."
- Home map current-unknown state: "Turn on sharing to see your distance here."
- Partner-unknown state: "Ask your partner to share location."
- The data contract says MVP location is latest partner location only, foreground-only, no history.

Why it matters:

Location is a high-trust permission. The current copy explains the benefit, but not enough of the boundary. "Ask your partner" can also create pressure in a relationship app. Paeonia should make opt-in feel respectful.

Fix:

- Include the boundary where the user makes the setting decision.
- Make partner-unknown copy neutral rather than pressuring.
- Keep the system permission copy plain and outcome-oriented.

Suggested copy:

| Current | Replace with |
| --- | --- |
| Your partner can see your latest location while sharing is on. | Your partner can see only your latest location while this is on. Paeonia does not show location history. |
| Ask your partner to share location. | When your partner turns sharing on, your distance will appear here. |
| Turn on sharing to see your distance here. | Turn on sharing to show your distance here. You can turn it off anytime. |

### P3: Marketing and app readiness language should be aligned before external traffic

Evidence:

- Marketing FAQ says the first release is being prepared and "When it is ready, this page will show you how to get started."
- `/join` says "When Paeonia launches, this link will connect you with your partner inside your shared space."
- The app already has active paywall, invite, pairing, and universal-link-adjacent surfaces.

Why it matters:

Pre-launch language is fine while the product is private. It becomes confusing if TestFlight users, App Review, or early invite users land on web pages that say the product is not ready while the app is asking them to subscribe or join.

Fix:

- Keep pre-launch copy while the app is private.
- Before TestFlight or App Review, change the marketing state to match the real channel: private beta, early access, or launched.
- Make `/join` say what happens today for installed and not-installed users.

Suggested copy for beta:

| Context | Copy |
| --- | --- |
| FAQ availability | Paeonia is in private testing. If your partner invited you, open the invite link on your iPhone. |
| Join fallback | Open this link on your iPhone to join your partner in Paeonia. If the app is not installed yet, ask your partner for the current invite instructions. |

### P3: Some dismiss and history controls are discoverable only through convention

Evidence:

- `PaeoniaTopBanner` has no visible dismiss control; it relies on swipe up, with only an accessibility dismiss action.
- Questions history and drawing history use icon-only clock toolbar buttons with accessibility labels.
- The ready map opens Maps on long press, but the visible card does not expose that affordance to sighted users.

Why it matters:

These are not blockers because the patterns are common enough on iOS, but they add small friction. Error banners in particular should be easy to dismiss without guessing a gesture.

Fix:

- Add a small visible close button to top banners, or auto-dismiss non-critical info banners while keeping error banners dismissible.
- Consider a short "History" text button where space allows, especially before users learn the clock icon.
- Expose "Open in Maps" as a visible secondary affordance if map use becomes important.

## Surface-Specific Notes

### Sign-In And Onboarding

- Sign-in is calm and focused. Legal/support links are available without leaving the app.
- The onboarding profile photo copy is clear: "Your partner will see this when you connect."
- The name rule is the main issue; make it explicit or remove the restriction.

### Pairing

- The invite code screen is mostly clear and uses good action hierarchy.
- "Check pairing" is understandable but a little mechanical. If users must tap it manually, "See if they joined" is warmer.
- "Make new code" should explain consequence if the old code stops working. Consider a confirmation if old invite links are revoked immediately.

### Home

- The paired profile header and widget tile are strong relationship-first elements.
- The hardcoded countdown tile is the most damaging home-screen issue.
- If Memories is not ready, the tab should not exist yet.

### Daily Challenge

- The one-question-at-a-time flow is good for focus.
- Local sending state is excellent and should be kept.
- Hiding the primary button while typing may be okay for layout, but watch usability: users must tap "Done" to reveal "Send answer". If testing shows hesitation, keep a compact Send button above the keyboard instead of hiding it.
- The partner answer reveal copy needs the most attention.

### Widget Drawing

- The tool surface is feature-complete: pen, pencil, eraser, undo, redo, color, size, canvas, history.
- First-use intent is not explicit enough. Rename around the shared widget outcome.
- The screen may feel dense on small devices. If visual testing shows compression, consider moving color/size controls into a bottom tool tray or collapsing advanced controls after first use.

### Settings

- The screen is clean and not overloaded.
- Location copy should add privacy boundaries.
- Notification copy is plain and understandable.

### Marketing

- The landing page has strong positioning and avoids public/social patterns.
- The mock phone is useful, but it shows product promises that the iOS app should not contradict with placeholders.
- Legal pages are still pre-launch placeholders. Before App Store submission, privacy and terms need final plain-language coverage.

## Recommended Implementation Order

1. Fix account deletion confirmation copy in English and Norwegian.
2. Remove or replace reachable placeholders: Memories tab, countdown hardcoded values, relationship-ended fallback, route-unavailable copy.
3. Clarify Daily Challenge partner-answer reveal states.
4. Split paywall invite entry from subscription purchase and standardize "invite code" terminology.
5. Rename widget drawing save flow around the shared widget outcome.
6. Tighten onboarding name validation copy.
7. Add privacy boundaries to location-sharing copy.
8. Align marketing readiness copy before external traffic.

## Suggested Verification

- Run a simulator pass on small iPhone and large Dynamic Type for sign-in, onboarding, paywall invite entry, Daily Challenge answer flow, widget drawing, settings, and relationship-ended state.
- Do a VoiceOver pass for invite code entry, top banner dismissal, Daily Challenge locked partner answer cards, widget drawing controls, and map card.
- Add UI snapshot coverage only where behavior is easy to regress: delete-account alert copy, placeholder-free tab bar, paywall invite mode, and Daily Challenge locked/revealed answer labels.
