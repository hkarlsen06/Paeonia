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
  - up to 5 images per partner per memory entry
  - one text note from either partner to create a memory entry
  - optional second partner note added later
  - voice notes in V1
  - countdown based on relationship milestones
  - widget with partner drawing support
  - opt-in partner location map
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
- Authenticated users without entitlement must still have a limited state where they can subscribe, restore purchases, accept an invite, sign out, or delete the account.
- Sign in with Apple private relay accounts must be supported as normal accounts.
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
- PaeoniaSyncService handles background upload/download.
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
  - block/leave/disconnect path
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
- Add `/.well-known/apple-app-site-association` for invite universal links. Completed with Apple Developer Team ID `48ZSLD4RMP`.
- Keep the site simple in Phase 1. The immediate goal is deployable structure, not finished copy/design.
- Later, use the marketing site as the canonical source for App Store privacy policy, terms, support URL, and universal links.

### iOS Project

- Create native iOS app in `ios/`. App target completed.
- Use an Xcode-managed `.xcodeproj`, matching Tidex. Completed for the app target.
- Keep the setup nearly identical to Tidex unless a deviation is discussed first.
- Use SwiftUI.
- Minimum deployment target: iOS 26.5. Completed for the app target.
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
  - limited authenticated
  - review access
  - unpaired
  - invite pending
  - paired
  - paired but paywalled
  - entitlement lost
  - entitlement restored
  - relationship ended notice
  - deleting account
- Create local store.
- Create first sync coordinator placeholder.
- Create localization catalog.
- Add generated localization-symbol workflow.

## Phase 2: Brand And Design Foundation

**Status: complete for MVP foundation.** Design foundation docs live in `docs/phase-2-design/`. Locked direction: premium calm, slightly custom native components, tactile key moments, SF/system typography across app and marketing, and a single plum-led visual theme instead of separate light/dark brand themes.

The delivered Paeonia logo, app-icon mark, and plum/pink palette are now the canonical visual baseline for marketing and native app work. Icon Composer material/depth tuning can still be adjusted as implementation polish, but the core brand direction is no longer deferred.

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

- Define color palette inspired by peonies, warmth, and privacy. Completed.
- Define the single plum-led app theme and accessibility behavior. Completed.
- Define typography roles. Completed.
- Define spacing scale. Completed.
- Define cards, buttons, sheets, empty states, and alerts. Completed.
- Define haptic patterns. Completed:
  - paired successfully
  - answer revealed
  - memory saved
  - streak continued

### App Icon

- Create an app icon before TestFlight. Completed.
- Direction: abstract paired peony/petal mark, not a literal flower photo. Completed.
- Requirements:
  - recognizable at small sizes
  - no text
  - no screenshots or UI elements
  - works in light and dark system contexts while preserving the plum brand background
  - works with iOS 26 icon appearances
  - export App Store marketing icon
  - keep source file in design assets
- Apple Icon Composer source/export assets are kept in the repo as the editable source of truth. The app currently compiles from a standard `.appiconset` PNG export to avoid Xcode asset compiler instability with the `.icon` package.
- Verify final icon in:
  - Home Screen. Completed manually.
  - Settings.
  - Spotlight.
  - App Store preview.
  - TestFlight.

## Phase 3: Backend And Data Model

**Status: implementation in progress.** The data contract and migration checklist are written, the migration suite exists, and database pgTAP tests exist. The remaining gate is local Supabase verification against a running Docker/OrbStack stack before treating the schema as locked.

Data-contract decisions are tracked in `docs/phase-3-data-contract.md`. Migration implementation order and checklist gates are tracked in `docs/phase-3-migration-checklist.md`.

New migrations must still be checked against both documents before they are written. Existing migrations should be verified locally with `supabase db reset --local` and `supabase test db --local supabase/tests` before being treated as the stable backend baseline.

### Core Tables

- `profiles`
- `relationship_pairs`
- `couples`
- `couple_members`
- `pairing_invites`
- `media_assets`
- `question_collections`
- `questions`
- `question_versions`
- `question_version_localizations`
- `question_answer_kinds`
- `couple_days`
- `daily_challenges`
- `daily_question_instances`
- `daily_question_shuffles`
- `daily_question_answers`
- answer detail tables
- `conversation_threads`
- `daily_question_threads`
- `memory_threads`
- `thread_messages`
- `thread_message_media`
- `widget_canvases`
- `widget_drawing_revisions`
- `location_sharing_preferences`
- `latest_partner_locations`
- `relationship_sync_events`
- `content_reports`
- `content_report_targets`
- `privacy_requests`
- entitlement tables
- internal invite secret table
- internal invite attempt/rate-limit table
- internal pair safety warning flags
- `streak_states`
- `couple_activity_events`
- `memories`
- `memory_notes`
- `memory_media`
- derived countdowns from `couples.started_on`
- `notification_preferences`
- `user_devices`
- internal notification outbox

### Security

- Use RLS by default.
- Every couple-owned row must be accessible only to the two couple members.
- Do not rely on client filtering for privacy.
- Add indexes for common couple and user queries.
- Add soft delete fields where needed.
- Store media with private buckets and signed URLs.
- Centralize upload/finalize/delete-retry state in `media_assets` for upload-backed media and drawing payloads.
- Store upload reservation context in `media_assets` from the first migration so finalize RPCs can prove the reserved path belongs to the expected user, couple, parent content, media type, bucket, and client operation.
- Include moderation/visibility state for reportable UGC from the first migrations.
- Avoid storing notification-sensitive content in push payloads unless the user explicitly opts in.
- Enforce shared couple subscription access in the database.
- Removing relationship access must be server-side, not only a local UI state.
- Admin/moderation operations may be SQL/service-role runbooks for MVP; do not add a custom admin UI before it is needed.
- Paeonia is not end-to-end encrypted for MVP. Private content is protected by RLS, private Storage, access checks, and operational controls, but trusted server-side systems can read content for sync, reports, support, legal, and safety handling.

### Sync Model

- Local-first writes.
- Dirty records for pending uploads.
- Soft deletes.
- Relationship-leave cleanup cron for content deletion after roughly one month.
- Use server-managed `updated_at` cursors with ID tie-breakers for pull sync, matching the mature Tidex direction.
- Keep server revisions on mutable local models for optimistic conflict detection and safe push handling.
- Use explicit tombstones/read-model payloads where direct table pulls cannot safely express deletes, reveal state, or relationship access changes.
- Add explicit relationship access-loss sync events so local-first clients hide stale relationship content when RLS stops returning rows.
- Classify each table as direct-sync, RPC/read-model, or internal-only before writing SQL migrations.
- Persist sync cursors only after a full page succeeds.
- Conflict policy:
  - last-write-wins only for low-risk settings
  - explicit merge or conflict state for memories and partner-submitted content

## Phase 4: Authentication And Pairing

**Status: mostly implemented, still needs device-level flow hardening.** Apple/Google auth, onboarding, profile-photo handling, paywall/StoreKit plumbing, app-account-token infrastructure, pairing invite flows, join-link handling, relationship-state routing, and paired-home routing exist. This phase is not complete until the full pre-auth to paired/paywalled flow is manually verified on device, account deletion is fully review-ready in app UI, and App Review/demo-account instructions are written.

### Authentication

- Support only:
  - Sign in with Apple
  - Google Sign-In
- Do not support passkeys, email/password, or email magic-link auth in MVP.
- Keep Sign in with Apple available because Google Sign-In is offered.
- Implement both auth surfaces as first-class MVP requirements. In progress.
- Do not require unnecessary profile fields. In progress.
- Add account deletion inside app before App Store submission. Backend/request plumbing exists; end-to-end UI and App Review validation still need completion.

### Pairing

- Create invite code or invite-link pairing.
- One active couple per user MVP.
- Show clear states:
  - not paired
  - invite pending
  - paired
  - partner left
  - disconnected
- Add ability to leave/disconnect couple.
- Add recovery path if invite expires.
- Pairing invite, preview, accept, celebration, and join-link handling are implemented enough to treat pairing as an active vertical slice.
- Pairing must remain invite-and-explicit-accept only; no searchable users or automatic pairing.

### Tests

- Pairing invite creation.
- Pairing acceptance.
- Expired invite.
- Already paired.
- Disconnect behavior.
- Account deletion cleanup.
- Device-level happy path: fresh install -> auth -> onboarding -> paywall -> invite -> paired home.

## Phase 5: Daily Ritual Core

**Status: next implementation priority.** The backend schema includes daily-question and answer tables, and the home card exists visually, but the app still shows placeholder daily prompt content and the Questions tab is not wired to real data. The next product slice should replace placeholder question UI with a small real daily challenge loop.

### Daily Challenge

- First slice:
  - Read or create today's daily challenge for the current user and couple.
  - Show up to three unanswered questions from the database.
  - Model question answer kinds correctly from day one. Each question version can allow one or two answer kinds.
  - Supported MVP answer kinds are text, photo, and voice note.
  - Implement the first narrow UI around the existing answer-kind contract, without hardcoding daily challenge as text-only.
  - If media/voice capture is too large for the first pass, keep the model/service/UI state answer-kind aware and ask before cutting behavior.
  - Replace `DailyPromptCard` placeholder content with real challenge progress.
  - Wire the Questions tab to today's challenge and partner-answered questions.
  - Reveal answer content only after both partners answered the same question instance.
  - Show that the partner answered, including when they answered, before revealing content.
  - Keep copy simple enough for a 16-year-old to understand.
- Later in the phase:
  - Let users shuffle unanswered candidate questions.
  - Limit each user to 5 shuffles per daily challenge across all three assigned questions.
  - Exclude shuffled questions from that user's candidate pool for 14 days.
  - Partners do not have to receive the same three questions.
  - A user's daily challenge is complete when they answer their own three questions.
  - Show partner-answered questions in a separate screen so the other partner can answer them too.
  - Create conversation thread only when someone sends the first follow-up message.
  - Use push notifications to remind users before streak expires, for example about one hour left.
  - Notify user when partner completes daily challenge.
  - Notification copy should explain answering is required before seeing what partner wrote.
  - Handle missed days gracefully.
  - Add time-zone rules:
    - compose couple day daily challenge when started, anchored to earliest partner timezone
    - do not expire streak before midnight in latest partner timezone
    - freeze each started couple day's timezone window

### Streaks

- Use couple-level streaks only.
- Continue streak when qualifying couple activity happens during couple day.
- Qualifying activity includes completing daily challenge or updating shared widget.
- Do not make streaks punitive.
- Add repair logic:
  - graceful restore button
  - no manipulative purchase-to-repair mechanic MVP

### Tests

- No challenge yet.
- One user answered.
- Partner answered but unrevealed.
- Both users answered and answer content revealed.
- Missed day.
- Time-zone boundary.
- Streak continuation.
- Streak repair.

## Phase 6: Memories And Media

**Status: not started as a product slice.** Backend schema exists, but the app should not build memories before the daily ritual loop is real. Memories remain MVP scope, but daily questions are the next priority.

### Timeline

- Add shared timeline.
- Support memory entries with:
  - up to 5 images per partner
  - one text note from either partner can create entry
  - optional second partner note added later
  - optional voice notes in V1
- Photos must support private upload, local caching, compression, deletion, offline pending states.
- Voice notes must support local drafts, upload retry, deletion, privacy-safe playback.
- Show empty states with clear next actions.
- Add local drafts so content is not lost.

### Moderation And Abuse Controls

Even if Paeonia is private one-to-one, user-generated content still needs safety controls.

- Add report/contact path.
- Add block/leave/disconnect path MVP safety cutoff.
- Report-and-leave flow should be labeled around the user's intent.
- Blocking closes current relationship and prevents future pairing between the two users unless blocking user explicitly unblocks later.
- Add support contact information.
- Add content deletion.
- Add internal SQL/service-role moderation process for reported content before public launch.
- Use manual/service-role quarantine for MVP moderation. Do not add external media scanning vendor unless explicitly revisited later.
- Defer scanner-specific backend fields until external scanning integration is selected.
- Custom admin UI is not required for MVP.
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

## Phase 7: Countdown, Notifications, Partner Location, Widget

**Status: partially implemented ahead of schedule.** Widget drawing, widget history/attribution, widget update notifications, paired-home widget card, and partner location map work have progressed substantially. Countdown remains visually placeholder-driven. Notification preferences and streak/daily-question notification behavior still need to be connected to the daily ritual.

### Countdown

- Create countdowns from relationship start date collected during onboarding.
- Default countdown:
  - if together under one year, count down next monthly milestone
  - after one year, count down next anniversary
- Allow later custom countdown next visit or another important date if it fits MVP.
- Make timezone behavior explicit.
- Support editing deletion.
- Use local notifications only permission.
- Current state: home has a branded milestone card with placeholder values; milestone calculation and relationship-date data wiring still need implementation.

### Push Notifications

- Request notification permission right moment, not on first launch.
- Support notification preferences:
  - streak expiry reminder
  - partner answered
  - new drawing
  - countdown reminders
- Avoid sensitive lock-screen content by default.
- Store typed, redacted push payloads by default; do not put answer text, note text, precise location, media URLs, invite codes, report details in pushes.
- Track APNs environment, delivery attempts, provider message id, failure reasons in notification outbox.
- Provide in-app settings to disable categories.
- Current state: widget update notifications exist. Daily-question/streak notification behavior still depends on Phase 5.

### Partner Location

- Partner location is part of MVP.
- Show map only after both partners explicitly opt in.
- Use foreground/manual location updates only in MVP. Do not request background location access.
- Store latest location only, not location history.
- Show when location last updated.
- Show partner avatar on map and dim stale location markers after 24 hours.
- Store consent audit fields for current location-sharing preference, including enable/disable timestamps and consent copy version.
- Reject or ignore stale offline location retries older than currently stored latest location.
- Delete location rows when sharing is disabled, relationship ends, or account deletion begins.
- Make App Store privacy labels and privacy policy account for precise location collection.
- Current state: couple map card, location view model, partner update paths, and location tests exist. Remaining work is device QA, permission/copy polish, and privacy-policy/App Store-label alignment.

### Widget

- Widget is a crucial MVP surface.
- Support widget-driven drawing experience: tap widget, draw in app, widget updates.
- Use PencilKit for in-app drawing canvas.
- Store canonical drawings as editable `PKDrawing` vector/stroke payloads.
- Do not store drawings canonical PNGs.
- Rasterize drawings on-device for display/network efficiency.
- Store canonical `.pkdrawing` payloads in private Storage metadata in Postgres.
- Keep raster previews as derived cache only.
- Consider widget modes:
  - latest partner drawing
  - countdown/milestone
  - today's ritual status
- Use App Group storage.
- Avoid showing sensitive content on widget by default.
- Provide privacy setting for widget content.
- Current state: widget drawing, App Group refresh path, deep-link opening, drawing history, author attribution, reliable reload handling, and partner update notifications exist. Remaining work is polish, privacy toggles, and connecting widget activity into the streak/daily ritual system.

### Tests

- Notification planner.
- Permission-denied behavior.
- Notification preference persistence.
- Partner location opt-in and opt-out.
- Location visibility only when both partners share.
- Widget payload generation.
- PencilKit drawing save/load.
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
- Review/test grants must be scoped, auditable, revocable, and expiring unless deliberately marked as lifetime grants.
- Leaving a relationship removes shared access for the departing/disconnected user.
- StoreKit restore must recover access for the paying account.

The paywall can be hard, but the review build must still be testable. Provide App Review with normal Apple/Google sign-in plus a review code that grants pre-paired review access, plus a screen recording of onboarding and invite pairing.

## Phase 9: Privacy, Legal, And Account Controls

This is not legal advice. Treat it as an implementation checklist before getting proper legal text reviewed.

### Required Before Submission

- Public privacy policy URL.
- In-app privacy policy link.
- Terms of service link.
- In-app account deletion.
- Data export or access request path. MVP may create a support/privacy request for manual fulfillment.
- Privacy request audit trail for manual fulfillment.
- Support/contact email.
- App Store privacy nutrition labels.
- App Review normal sign-in plus pre-paired review code or clear reviewer instructions.
- Screen recording showing onboarding and invite pairing.

### Privacy Policy Must Cover

- What data is collected.
- Why it is collected.
- How it is stored.
- Whether it is linked to identity.
- Whether it is shared with vendors.
- Retention and deletion.
- Media handling.
- Precise partner location handling.
- Report snapshots and moderation review handling.
- Trusted server-side access for support, safety, legal, deletion, export/access requests, and cleanup.
- Backup retention and cleanup windows.
- Notifications.
- Analytics, if any.
- Contact/support.

### App Privacy Labels

Prepare accurate App Store Connect answers for:

- contact info
- identifiers
- user content, including messages/photos/notes if collected
- precise location, because partner location ships in MVP
- diagnostics
- purchases, if subscriptions exist
- usage data, if analytics exist
- support/privacy request data, if collected

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
- Include normal sign-in, pre-paired review code, and optional test pairing instructions.
- Ensure all in-app purchases are visible and reviewable.

## Phase 11: Quality Gate Before TestFlight

### Functional QA

- Fresh install.
- Sign up.
- Sign in.
- Pair with partner.
- Complete daily challenge.
- Reveal after both answer.
- Create memory.
- Delete memory.
- Add countdown.
- Edit countdown.
- Enable/disable partner location.
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
  - daily challenge completion
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
- User-generated content lacks reporting/contact/safety-cutoff mechanisms.
- Blocking/re-pair prevention is unclear.
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
10. Add memory timeline with notes, up to 5 images per partner, and voice notes.
11. Add relationship milestone countdown.
12. Add notification preferences and local/push notifications.
13. Add opt-in partner location.
14. Add PencilKit-based widget drawing flow.
15. Add privacy/account deletion/export/leave relationship controls.
16. Add app icon, launch screen, screenshots, and metadata.
17. Run internal TestFlight.
18. Run external TestFlight.
19. Submit 1.0.

## Recommended 1.0 Cut Line

Ship 1.0 when these are true:

- A couple can pair reliably.
- One partner can pay and both partners receive access.
- Each person can complete a daily ritual.
- Answers reveal correctly.
- Streak reminders work without exposing sensitive content.
- A memory with text, images, and voice can be saved and recovered.
- Relationship milestone countdown works.
- Partner location works only after both partners opt in and clearly shows when it was updated.
- Stale partner location markers dim after 24 hours.
- Notifications are useful but not invasive.
- The widget drawing flow works with PencilKit stroke/vector storage and no private leakage by default.
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
