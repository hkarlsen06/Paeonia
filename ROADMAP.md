# Paeonia MVP Roadmap

This roadmap is focused on getting Paeonia to a review-ready iOS MVP with enough product value, polish, privacy handling, and App Store preparation to pass App Review.

## Guiding MVP Definition

Paeonia should launch as a small but complete private space for two people.

The MVP is not a clone of existing long-distance relationship apps. It should prove the core promise:

> A private place for the two of you.

The first release should be reliable, emotionally clear, and narrow. Cut features before shipping anything fragile.

## Phase 0: Product And Compliance Decisions

**Status: complete.** The decisions below are locked for MVP planning unless explicitly revisited.

### Product Scope

- First-release feature set:
  - couple pairing through invite-and-accept only
  - onboarding with relationship start date
  - daily check-in questions
  - private answers revealed after both partners respond
  - shared streak with reminder before expiry
  - memory timeline
  - up to 5 images per memory entry
  - one text note from either partner to create a memory entry
  - optional second partner note added later
  - voice notes in V1
  - countdown based on relationship milestones
  - widget with partner drawing support
  - push notifications for streak reminders, new drawings, and partner answers
  - hard paywall with shared couple entitlement
  - settings, privacy, export/delete account, and leave relationship controls
- Deferred from MVP:
  - AI
  - public profiles
  - multiple couples
  - prompt marketplace
  - advanced photo editing
  - public discovery/search
  - ads

### Monetization

- Paeonia will not launch free.
- The MVP uses a hard paywall.
- Only one partner needs to pay; both partners receive access through the couple entitlement.
- Subscription entitlement must be enforced server-side, not only locally.
- The paywall must still be clear, honest, and App Review-safe:
  - price
  - billing period
  - renewal behavior
  - trial terms, if any
  - restore purchases
  - manage subscription link
  - what is unlocked for both partners

### Offline-First Behavior

- Follow Tidex's local-first model because it makes the app feel faster and more reliable.
- App launches offline.
- Existing relationship state, memories, answers, drawings, voice notes, countdowns, and widget payloads are readable offline when cached locally.
- New local changes should be saved immediately and marked pending/dirty.
- A SyncCoordinator-style system handles background upload/download.
- Pending writes sync later without losing user content.
- Sync state should be visible where it matters, but ordinary use should not feel blocked by the network.

### Couple Disconnect Behavior

- Leaving a relationship immediately removes the server-side entitlement to view shared relationship content.
- On the next sync, the prior shared relationship content should disappear from the leaving/disconnected user's app.
- Historical content is not deleted immediately.
- A backend cron job should permanently delete the relationship content after roughly one month.
- The app must clearly warn the user before leaving a relationship.

### Compliance Decisions

- Target audience during product design: 16+.
- App Store age rating will be determined by Apple's questionnaire.
- Aim for the broadest App Store rating that is honest for the actual shipped content and features.
- Paeonia has user-generated content:
  - text notes
  - check-in answers
  - images
  - voice notes
  - drawings
  - display names/profile details
- MVP safety model:
  - private one-to-one couple space only
  - no public discovery
  - no random matching
  - no searchable profiles
  - invite code or invite-link pairing
  - explicit accept flow
  - report/contact support path
  - leave/disconnect path
  - delete own account/content
- Data retention:
  - account deletion removes or anonymizes profile, devices, relationship membership, private content, and media
  - deleted memories should disappear for both partners after sync
  - leaving a relationship hides prior shared content by removing access entitlement
  - backend cron permanently deletes disconnected relationship content after roughly one month
  - media is private and deleted with the owning content/account according to the retention policy
  - realistic backup retention must be disclosed in the privacy policy
- Analytics:
  - no ads
  - no tracking
  - no IDFA
  - no ad SDKs
  - functional database state is not considered product tracking by itself
  - avoid third-party analytics for MVP unless there is a clear reason

### Backend Decision

- Use Supabase.
- Use RLS by default.
- Use Supabase Auth unless a better reason appears later.
- Prefer user JWT + RLS for ordinary app operations.
- Use service-role flows only for work that truly requires privileged access, such as cron cleanup, admin deletion, or notification fanout internals.
- Keep the database as the source of truth for couple membership, relationship access, and shared subscription entitlement.

## Phase 1: Repository And Project Foundation

**Status: complete.** The repo, pnpm workspace, marketing shell, Cloudflare static files, CI smoke workflow, Xcode-managed iOS targets, build/test wrappers, app and widget entitlements, initial symbol-based localization, root app state, local store placeholder, and sync coordinator placeholder are in place.

### Repo Setup

- Initialize git. Completed.
- Add `.gitignore`. Completed.
- Add signed initial commit.
- Create GitHub repository when ready.
- Use `paeonia.no` as the canonical public domain.
- Add issue labels or a simple project board:
  - MVP
  - app-review
  - privacy
  - design
  - backend
  - tests
  - polish

### Marketing Site

- Create `marketing/` as a static Next.js app, matching Tidex's marketing-site structure where practical. Completed.
- Configure static export for Cloudflare Pages. Completed.
- Use `paeonia.no` as the production domain.
- Add the core public routes needed for App Store readiness:
  - `/`
  - `/privacy`
  - `/terms`
  - `/support`
- Reserve a universal-link route for invite pairing, for example:
  - `/join/[inviteCode]`
- Keep the site simple in Phase 1. The immediate goal is deployable structure, not finished copy/design.
- Later, use the marketing site as the canonical source for App Store privacy policy, terms, support URL, and universal links.

### iOS Project

- Create native iOS app in `ios/`. App target completed.
- Use an Xcode-managed `.xcodeproj`, matching Tidex. Completed for the app target.
- Keep the setup nearly identical to Tidex unless a deviation is discussed first.
- Use SwiftUI.
- Minimum deployment target: iOS 26.6. Completed for the app target.
- Set bundle identifier. Completed for the app target.
- Add app display name: `Paeonia`. Completed for the app target.
- Create app, widget, notification service extension, unit test, and UI test targets from day one. Completed.
- Treat the widget as central to the product experience, not as a later add-on.
- Include App Group support for app/widget shared local state. Completed for the app and widget targets.
- Configure Associated Domains immediately for `applinks:paeonia.no`. Completed for the app target.
- Create String Catalog localization from day one with generated symbols. Completed for the app target.
- Start with English and Norwegian Bokmal. Completed for the seed catalog.
- Add SwiftLint or equivalent static checks. Completed.
- Add scripts for build/test once stable. Completed:
  - `./scripts/xcode-build-agent.sh`
  - `./scripts/xcode-test-agent.sh`
- Add app-wide folders. Completed locally:

```text
ios/PaeoniaApp/
├── App/
├── Features/
├── Services/
├── Storage/
├── Models/
├── Shared/
└── Resources/
```

- Preserve the feature-first structure as a maintainability rule.
- Keep feature-specific views, view models, models, components, and utilities inside their feature folder.
- Move code into `Shared/` only when it is genuinely reusable across features.

### Architecture Foundation

- Create app coordinator/root state:
  - launching
  - unauthenticated
  - onboarding
  - unpaired
  - paired
  - paywalled, if needed
- Create local store.
- Create first sync coordinator placeholder.
- Create localization catalog.
- Add generated localization-symbol workflow.

## Phase 2: Brand And Design Foundation

### Brand

- Lock name: `Paeonia`.
- Lock pronunciation: `pay-OH-nee-uh`.
- Write short product description:
  - "A private place for the two of you."
- Define brand attributes:
  - private
  - intimate
  - calm
  - reliable
  - premium
  - emotionally warm

### Visual System

- Define color palette inspired by peonies, warmth, and privacy.
- Define light and dark mode from the start.
- Define typography roles.
- Define spacing scale.
- Define cards, buttons, sheets, empty states, and alerts.
- Define haptic patterns:
  - paired successfully
  - answer revealed
  - memory saved
  - streak continued

### App Icon

- Create an app icon before TestFlight.
- Direction: abstract peony/petal mark, not a literal flower photo.
- Requirements:
  - recognizable at small sizes
  - no text
  - no screenshots or UI elements
  - works in light and dark contexts
  - works with iOS 26 icon appearances
  - export App Store marketing icon
  - keep source file in design assets
- Consider Apple Icon Composer for layered Liquid Glass icon work.
- Verify final icon in:
  - Home Screen
  - Settings
  - Spotlight
  - App Store preview
  - TestFlight

## Phase 3: Backend And Data Model

Use Supabase. Design the backend before UI implementation goes too far.

### Core Tables

- `profiles`
- `couples`
- `couple_members`
- `pairing_invites`
- `daily_prompts`
- `prompt_responses`
- `streak_states`
- `memories`
- `memory_notes`
- `media_assets`
- `voice_notes`
- `widget_drawings`
- `widget_drawing_strokes`
- `countdowns`
- `notification_preferences`
- `user_devices`
- `subscription_entitlements`
- `relationship_leave_events`

### Security

- Use RLS by default.
- Every couple-owned row must be accessible only to the two couple members.
- Do not rely on client filtering for privacy.
- Add indexes for common couple and user queries.
- Add soft delete fields where needed.
- Store media with private buckets and signed URLs.
- Avoid storing notification-sensitive content in push payloads unless the user explicitly opts in.
- Enforce shared couple subscription access in the database.
- Removing relationship access must be server-side, not only a local UI state.

### Sync Model

- Local-first writes.
- Dirty records for pending uploads.
- Soft deletes.
- Relationship-leave cleanup cron for content deletion after roughly one month.
- Server revisions or timestamps.
- Conflict policy:
  - last-write-wins only for low-risk settings
  - explicit merge or conflict state for memories and partner-submitted content

## Phase 4: Authentication And Pairing

### Authentication

- Support only:
  - Sign in with Apple
  - Google Sign-In
  - passkeys
- Do not support email/password or email magic-link auth in the MVP.
- Keep Sign in with Apple available because Google Sign-In is offered.
- Implement all three auth surfaces as first-class MVP requirements.
- Do not require unnecessary profile fields.
- Add account deletion inside the app before App Store submission.

### Pairing

- Create invite code or invite-link pairing.
- One active couple per user for MVP.
- Show clear states:
  - not paired
  - invite pending
  - paired
  - partner left
  - disconnected
- Add ability to leave/disconnect couple.
- Add recovery path if invite expires.

### Tests

- Pairing invite creation.
- Pairing acceptance.
- Expired invite.
- Already paired.
- Disconnect behavior.
- Account deletion cleanup.

## Phase 5: Daily Ritual Core

### Daily Prompt

- Show one daily check-in question/prompt.
- Let each partner answer privately.
- Reveal both answers only after both have responded.
- Use push notifications to remind users before the streak expires, for example when there is about one hour left.
- Notify a user when their partner has answered a question that the user already answered.
- Handle missed days gracefully.
- Add time-zone rules:
  - decide if the daily prompt uses each user local day or a shared couple day
  - make the rule explicit in code and tests

### Streaks

- Use forgiving rules.
- Do not make streaks punitive.
- Add repair logic:
  - timezone grace window
  - optional one-day repair
  - no manipulative purchase-to-repair mechanic for MVP

### Tests

- One user answered.
- Both users answered.
- Reveal state.
- Missed day.
- Time-zone boundary.
- Streak continuation.
- Streak repair.

## Phase 6: Memories And Media

### Timeline

- Add shared timeline.
- Support memory entries with:
  - up to 5 images
  - one text note from either partner to create the entry
  - optional second partner note added later
  - optional voice notes in V1
- Photos must support private upload, local caching, compression, deletion, and offline pending states.
- Voice notes must support local drafts, upload retry, deletion, and privacy-safe playback.
- Show empty states with clear next actions.
- Add local drafts so content is not lost.

### Moderation And Abuse Controls

Even if Paeonia is private one-to-one, user-generated content still needs safety controls.

- Add report/contact path.
- Add block or disconnect path.
- Add support contact information.
- Add content deletion.
- Add internal admin/removal process for reported content if backend moderation is required.
- Publish terms/community standards before submission.

### Tests

- Create memory.
- Edit memory.
- Delete memory.
- Add partner note later.
- Upload media failure.
- Voice note recording/upload failure.
- Offline draft recovery.
- Partner visibility.

## Phase 7: Countdown, Notifications, And Widget

### Countdown

- Create countdowns from the relationship start date collected during onboarding.
- Default countdown:
  - if together under one year, count down to the next monthly milestone
  - after one year, count down to the next anniversary
- Allow a later custom countdown to next visit or another important date if it fits the MVP.
- Make timezone behavior explicit.
- Support editing and deletion.
- Use local notifications only with permission.

### Push Notifications

- Request notification permission at the right moment, not on first launch.
- Support notification preferences:
  - streak expiry reminder
  - partner answered
  - new drawing
  - countdown reminders
- Avoid sensitive lock-screen content by default.
- Provide in-app settings to disable categories.

### Widget

- The widget is a crucial MVP surface.
- Support drawing on the widget experience.
- Store drawings as vectorized, stroke-based data.
- Do not store drawings as canonical PNGs.
- Rasterize drawings on-device for display and network efficiency.
- Send compact drawing payloads to reduce egress cost.
- Consider widget modes:
  - latest partner drawing
  - countdown/milestone
  - today's ritual status
- Use App Group storage.
- Avoid showing sensitive content on the widget by default.
- Provide a privacy setting for widget content.

### Tests

- Notification planner.
- Permission-denied behavior.
- Notification preference persistence.
- Widget payload generation.
- Drawing stroke encoding/decoding.
- Drawing rasterization.
- Countdown boundary dates.

## Phase 8: Monetization

Paeonia launches paid in 1.0 with a hard paywall. This increases implementation and App Review burden, so StoreKit and entitlements must be treated as MVP-critical infrastructure.

- Use StoreKit.
- Configure subscription group in App Store Connect.
- Only one partner needs to pay.
- Both partners receive access through the couple entitlement.
- Enforce entitlement on the backend as well as locally.
- Clearly explain what users get before purchase.
- Include price, duration, renewal behavior, trial terms, and cancellation path.
- Include restore purchases.
- Include manage subscription entry in settings.
- Ensure paid access works across all supported devices.
- Do not require tasks like social posting, contact uploads, or daily check-ins to get paid value.
- Add App Review notes explaining subscription behavior.

### Entitlement Rules

- If either partner has an active subscription, the couple is entitled.
- Entitlement should survive normal sign-out/sign-in.
- Entitlement should be revoked when neither partner has an active subscription.
- Leaving a relationship removes shared access for the departing/disconnected user.
- StoreKit restore must recover access for the paying account.

The paywall can be hard, but the review build must still be testable. Provide App Review with credentials/instructions that demonstrate the paid experience.

## Phase 9: Privacy, Legal, And Account Controls

This is not legal advice. Treat it as an implementation checklist before getting proper legal text reviewed.

### Required Before Submission

- Public privacy policy URL.
- In-app privacy policy link.
- Terms of service link.
- In-app account deletion.
- Data export or access request path.
- Support/contact email.
- App Store privacy nutrition labels.
- App Review demo account or clear reviewer instructions.

### Privacy Policy Must Cover

- What data is collected.
- Why it is collected.
- How it is stored.
- Whether it is linked to identity.
- Whether it is shared with vendors.
- Retention and deletion.
- Media handling.
- Notifications.
- Analytics, if any.
- Contact/support.

### App Privacy Labels

Prepare accurate App Store Connect answers for:

- contact info
- identifiers
- user content, including messages/photos/notes if collected
- diagnostics
- purchases, if subscriptions exist
- usage data, if analytics exist

Keep third-party SDKs minimal because their data practices must be included too.

## Phase 10: App Store Assets

### App Store Connect

- App name: `Paeonia`
- Subtitle.
- Promotional text.
- Description.
- Keywords.
- Support URL.
- Marketing URL, optional.
- Privacy policy URL.
- Category.
- Age rating questionnaire.
- Copyright.
- App Review contact info.
- App Review notes.

### Screenshots

Prepare screenshots that show the app in use, not just splash/title art.

Minimum recommended screenshot set:

1. Private space for two
2. Daily prompt/reveal
3. Memory timeline
4. Countdown
5. Widget
6. Privacy/settings

Avoid showing real private content in screenshots. Use realistic sample content.

### Metadata Integrity

- Do not claim features that are not in the build.
- If subscriptions exist, indicate what requires payment.
- Make review notes specific.
- Include credentials/test pairing instructions.
- Ensure all in-app purchases are visible and reviewable.

## Phase 11: Quality Gate Before TestFlight

### Functional QA

- Fresh install.
- Sign up.
- Sign in.
- Pair with partner.
- Answer daily prompt.
- Reveal after both answer.
- Create memory.
- Delete memory.
- Add countdown.
- Edit countdown.
- Notification permission denied.
- Notification permission granted.
- Widget privacy on/off.
- Account deletion.
- Sign out/sign in.
- Offline launch.
- Slow network.
- App killed and relaunched.

### Device Coverage

- Small iPhone.
- Large iPhone.
- Latest iOS version.
- Previous supported iOS version, if supported.
- Light mode.
- Dark mode.
- Dynamic Type.
- Reduce Motion.
- VoiceOver smoke pass.

### Technical QA

- No crashes in ordinary flows.
- No broken empty states.
- No hardcoded user-facing strings.
- No missing localization keys.
- No console spam that hides real errors.
- No private content in logs.
- No secrets in repo.
- No broken privacy/account links.
- No missing app icon sizes/assets.

## Phase 12: TestFlight Beta

### Internal TestFlight

- Upload build.
- Verify install and launch from TestFlight.
- Verify app icon and display name.
- Test App Store receipt/subscription environment if monetized.
- Test push notifications with production-like APNs setup.

### External TestFlight

- Prepare beta review notes.
- Explain account/pairing flow.
- Provide test account/invite instructions.
- Recruit a small set of couples.
- Track:
  - pairing completion
  - daily prompt completion
  - notification reliability
  - widget refresh behavior
  - memory creation
  - crashes
  - confusing copy

## Phase 13: App Review Submission

### Final Checklist

- Build is production configured.
- App icon final.
- Launch screen final.
- Privacy policy URL live.
- Support URL live.
- Terms URL live.
- Account deletion works.
- Report/contact flow works.
- App privacy labels completed.
- Screenshots are accurate.
- Metadata is accurate.
- In-app purchases approved or submitted with the build, if used.
- Review notes include:
  - what Paeonia does
  - why account login is required for couple pairing
  - demo credentials or pairing instructions
  - subscription details, if applicable
  - any special notification/widget behavior

### Rejection-Risk Areas To Audit

- App feels too empty without a partner.
- Login is required without clearly account-based functionality.
- User-generated content lacks reporting/blocking/contact mechanisms.
- Account deletion missing.
- Privacy policy missing or incomplete.
- Privacy labels inaccurate.
- Subscription terms unclear.
- Paywall blocks all meaningful functionality.
- Screenshots imply unavailable features.
- App icon or metadata too similar to another app.
- Widget exposes sensitive content without consent.
- Push notifications reveal private content on lock screen.

## Suggested Build Order

1. Create iOS app skeleton.
2. Add design system and localization.
3. Add local store and repositories.
4. Add Supabase schema, RLS, and local sync foundations.
5. Add auth.
6. Add subscription/paywall and shared couple entitlement.
7. Add invite-and-accept pairing.
8. Add daily check-in and reveal.
9. Add streak logic and expiry reminders.
10. Add memory timeline with notes, up to 5 images, and voice notes.
11. Add relationship milestone countdown.
12. Add notification preferences and local/push notifications.
13. Add stroke-based widget drawing flow.
14. Add privacy/account deletion/export/leave relationship controls.
15. Add app icon, launch screen, screenshots, and metadata.
16. Run internal TestFlight.
17. Run external TestFlight.
18. Submit 1.0.

## Recommended 1.0 Cut Line

Ship 1.0 when these are true:

- A couple can pair reliably.
- One partner can pay and both partners receive access.
- Each person can complete a daily ritual.
- Answers reveal correctly.
- Streak reminders work without exposing sensitive content.
- A memory with text, images, and voice can be saved and recovered.
- Relationship milestone countdown works.
- Notifications are useful but not invasive.
- The widget drawing flow works with stroke-based storage and no private leakage by default.
- Leaving a relationship hides shared content after sync and schedules backend deletion.
- Account deletion works.
- Privacy policy and App Store privacy labels are accurate.
- The app feels polished in its narrow scope.

Defer anything that threatens reliability:

- complicated media editing
- public profiles
- prompt marketplace
- AI-generated prompts
- multiple partners/couples
- Android/web companion
- advanced analytics

## Official Apple References

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Review preparation: https://developer.apple.com/distribute/app-review/
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Manage app privacy in App Store Connect: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Auto-renewable subscriptions: https://developer.apple.com/app-store/subscriptions/
- App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
- Icon Composer: https://developer.apple.com/icon-composer/
