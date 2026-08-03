# Implementation Map

This is the first stop when an agent needs to find the current owner of a Paeonia behavior. Keep this file factual and source-oriented; durable rules still belong in `AGENTS.md`.

## Launch, Root State, And Navigation

- `ios/PaeoniaApp/App/RootView.swift`: root loading surface, top banner mounting, and first app surface switching. Mounts the cold-launch intro (`LaunchExperienceView`) over the routed content and keeps it up until the intro signals it has fully unmasked the app (not just when `state` leaves `.launching`). After pairing and the celebration settle, it presents the one-time notification primer before asking iOS for permission.
- `ios/PaeoniaApp/Features/Auth/LaunchExperienceView.swift`: the cold-launch intro that continues the system launch screen — the composed petal mark stays static while auth/access and the routed surface are prepared, then the two petal halves (`PaeoniaMarkPetalLeft`/`PaeoniaMarkPetalRight`, split from `PaeoniaMark` on the same viewBox) pull apart like a loaded spring, release, and collapse back at full speed. They are never seen stopping: at ~88% of the release the shockwave fires and the petals flick out over ~50ms, reaching zero opacity exactly as the fall lands (still short of composed). The shockwave unmasks the first app surface (a growing `destinationOut` hole in the plum backdrop, expanding past the corners); eligible surfaces may cue their own content at that point, while the paired Home cards remain stationary. No wordmark reveal. The animated portion starts only after `contentReady` and respects Reduce Motion (holds the composed mark, exits with a fade — no spring, no shockwave).
- `ios/PaeoniaApp/Features/Auth/LaunchReveal.swift`: the coordination glue between the intro and the surface it uncovers — `EnvironmentValues.launchContentRevealed` (cues eligible content as the intro exits) and `EnvironmentValues.launchIntroComplete` (true once the intro fully finishes), both set on the routed content in `RootView` and defaulting `true` outside the cold launch, plus reusable entrance modifiers for surfaces that still use a staggered reveal. `PairedHomeView` keeps its Home cards stationary on cold launch so the petal spring remains the focal motion; `CoupleMapCard`'s first flame sweep waits on `launchIntroComplete` so it plays after the intro, not hidden behind the overlay.
- `ios/PaeoniaApp/Features/Auth/LaunchExperienceSequence.swift`: the pure, unit-tested phase machine behind the intro (`mark → spring → revealing → finished`); enforces that the app is only revealed once both the spring's landing and content readiness are satisfied. Tests in `ios/PaeoniaAppTests/LaunchExperienceSequenceTests.swift`.
- `ios/PaeoniaApp/Features/Auth/AuthBaselineViews.swift`: `AuthLaunchingView` is the quiet, copy-free in-flow loading surface used while a feature's `isPresentationReady == false` (e.g. `PairingInviteView`, `PaywallView`) — separate from the one-time cold-launch intro above.
- `ios/PaeoniaApp/Features/Auth/Welcome/WelcomeView.swift`: pre-auth entry surface. Owns the three-screen value carousel, transition to sign-in, and first-class invite-code sheet.
- `ios/PaeoniaApp/Features/Auth/Welcome/WelcomeCarousel.swift`: pure welcome-page order and localized content model. Tests in `ios/PaeoniaAppTests/WelcomeCarouselTests.swift`.
- `ios/PaeoniaApp/Features/Auth/Welcome/WelcomeInviteCodeSheet.swift`: pre-auth invite-code capture. The code is retained through sign-in and redeemed through the normal pairing path.
- `ios/PaeoniaApp/Features/Auth/SignInView.swift`: Apple/Google sign-in controls and pre-auth privacy, terms, and support links.
- `ios/PaeoniaApp/App/RootViewModel.swift`: launch-adjacent auth/access/pairing state and `PresentationReadinessProviding` readiness.
- `ios/PaeoniaApp/App/RootPrivacyLifecycle.swift`: cold-launch/foreground draining and bounded recovery for durable local privacy-purge retries; blocks a new paired route and sync startup until an older owner-scoped purge has completed.
- `ios/PaeoniaApp/App/MainTabView.swift` and `ios/PaeoniaApp/App/MainTab.swift`: tab layout and high-level feature entry points.
- `ios/PaeoniaApp/App/DeveloperScenarios/`, `ios/PaeoniaApp/App/RootFeatureDependencies.swift`, and the shared `Scenarios` Xcode scheme: Debug-only deterministic state launcher plus interactive local flows through the production root. It replaces OAuth, StoreKit, Supabase, APNs, sync, and persistence boundaries with in-memory dependencies. Use `PAEONIA_SCENARIO=<id>` or `-paeonia-scenario <id>` for direct UI-test launches. The extension contract is in `docs/developer-scenario-harness.md`.
- `ios/PaeoniaApp/App/RootNoticeLocalization.swift`: root-level user-facing notice copy.
- `ios/PaeoniaAppTests/AccessRouteResolverTests.swift`: access route behavior around launch and relationship access.

When a launch-time network call is cancelled with `NSURLErrorCancelled` / `URLError.cancelled` shortly after render, inspect `.task(id:)` keys before hiding the error. The known Daily Challenge case is documented in `AGENTS.md`.

## Daily Challenge

- `ios/PaeoniaApp/Features/DailyChallenge/Challenge/DailyChallengeView.swift`: screen composition, loading hooks, and presentation flow.
- `ios/PaeoniaApp/Features/DailyChallenge/Challenge/DailyChallengeViewModel.swift`: screen state, participant refresh, loading, answering, and reveal coordination.
- `ios/PaeoniaApp/Features/DailyChallenge/Challenge/DailyChallengeStepBar.swift`: step/progress UI for the main challenge flow.
- `ios/PaeoniaApp/Features/DailyChallenge/Challenge/DailyChallengeNoticeLocalization.swift`: localized title/message mapping for `DailyChallengeViewModel.Notice`.
- `ios/PaeoniaApp/Features/DailyChallenge/Models/DailyChallengeModels.swift`: UI/domain models and answer-kind shape.
- `ios/PaeoniaApp/Features/DailyChallenge/Models/DailyChallengeRemoteRows.swift`: DTOs matching Supabase RPC/read-model rows.
- `ios/PaeoniaApp/Features/DailyChallenge/Data/DailyChallengeService.swift`: Supabase calls for challenge/day/question/answer behavior.
- `ios/PaeoniaApp/Features/DailyChallenge/Data/DailyChallengeDraftStore.swift`: local answer draft persistence.
- `ios/PaeoniaApp/Features/DailyChallenge/Data/DailyChallengeSnapshotCache.swift`: local-first cold-launch cache. The live service writes the raw `DailyChallengeRemoteSnapshotRow` (keyed per user) on every successful snapshot load; `DailyChallengeViewModel.configure` seeds `snapshot`+`streak` from it via `DailyChallengeRemoteSnapshotRow.loadResult` before the network `reload()`, so returning users see real content (not placeholders) on the first frame. The centralized local privacy purger clears it on relationship access loss or user departure.
- `ios/PaeoniaApp/Features/DailyChallenge/Data/DailyChallengePendingOperationHandler.swift`: local-first retry handling for queued challenge writes.
- `ios/PaeoniaApp/Features/DailyChallenge/Components/DailyChallengeQuestionViews.swift`: reusable question and answer UI pieces.
- `ios/PaeoniaApp/Features/DailyChallenge/Components/DailyChallengeMediaViews.swift`: image/media display for answers.
- `ios/PaeoniaApp/Features/DailyChallenge/Components/DailyChallengeReadCard.swift`: the shared read-only question card (prompt + status + revealed answers), used by the Questions tab's single read list and the history flow. `DailyChallengeQuestion.list` (in `DailyChallengeModels.swift`) is the shared row→question mapping behind both today's snapshot and history. The Questions tab shows the partner's and the user's questions in one list (`DailyChallengeSnapshot.readOverviewQuestions`), not split into "their"/"mine" sections.
- `ios/PaeoniaApp/Features/DailyChallenge/AnswerFlow/DailyChallengeAnswerFlow.swift`: answering flow and text/photo/voice/partner-choice composition.
- `ios/PaeoniaApp/Features/DailyChallenge/AnswerFlow/DailyPartnerAnswerFlow.swift`: answering one partner-authored question. On send it holds (`awaitAnswerReveal`) and then turns the cover over to the revealed exchange (partner's reply on top) instead of closing — so the reward doesn't depend on finding the card in the list afterward. Offline/queued sends just close and reveal later on the card.
- `ios/PaeoniaApp/Features/DailyChallenge/AnswerFlow/DailyChallengeCameraPicker.swift`: camera/photo picker used by the answer flow.
- `ios/PaeoniaApp/Features/DailyChallenge/History/DailyChallengeHistory.swift`: pure date-grouping for the history overview (`DailyChallengeHistoryDay`, newest-day-first grouping, local-date parsing).
- `ios/PaeoniaApp/Features/DailyChallenge/History/DailyChallengeHistoryViewModel.swift`: history load/state/readiness, banner-routed reload errors. `ViewState.content` carries `Content { pendingPartnerQuestions, days }`; the partner's still-unanswered questions are read live from the daily-challenge snapshot (`answerablePartnerQuestions`, injected via the `pendingPartnerQuestions` closure from `DailyChallengeViewModel.makeHistoryViewModel()`), not from the answered-history RPC, and are deduped against the loaded history.
- `ios/PaeoniaApp/Features/DailyChallenge/History/DailyChallengeHistoryView.swift`: the History full-screen cover — title, close, a top "waiting for you" section of answerable partner cards (same CTA as the Questions tab, gated by `hasCompletedRequiredDailyQuestions`, zooms into `DailyPartnerAnswerFlow` and reloads on close), then centered date dividers + read cards, plus empty/loading/error states. Needs the shared `DailyChallengeViewModel`. Opened from the Questions-tab toolbar History button in `DailyChallengeView.swift`.
- `ios/PaeoniaApp/Features/DailyChallenge/Audio/DailyVoiceAnswerViews.swift`, `DailyVoiceRecorder.swift`, and `DailyVoiceAudioSession.swift`: voice recording/playback UI and audio session handling.
- `ios/PaeoniaApp/Features/DailyChallenge/Streak/CoupleStreak.swift`: couple streak calculation and state.
- `ios/PaeoniaApp/Services/Media/DailyAnswerMediaDraftStore.swift`, `DailyAnswerMediaUploadService.swift`, and `DailyAnswerMediaImageService.swift`: photo/voice draft storage, upload, and display support.
- `ios/PaeoniaAppTests/DailyChallengeTests.swift`: main regression suite for question state, answer flow, reveal behavior, cancellation, and media handling.

Question content is authored in `supabase/questions/`; read `docs/couple-question-guidelines.md` before changing prompts. For combined `text` + `photo` or `text` + `partner_choice` questions, both composers can be shown at once and each part is optional.

Questions history reads through `public.get_daily_questions_history()` and `public.get_daily_answer_history_details()` (migration `20260628234249_add_daily_questions_history_rpcs.sql`): thin public wrappers over security-definer internal implementations, scoped to instances the viewer has answered, reusing the existing per-answer reveal rules.

A daily question belongs to the couple-local day of its *latest* answer, not its seed day (migration `20260629004244_place_daily_questions_in_latest_answer_day.sql`). `get_daily_questions_history` returns `effective_local_date` (the latest answer's date in the couple's anchor timezone) and `DailyChallengeHistory.grouped` buckets on it; `get_today_daily_questions` keeps a carried-over instance in the Questions tab while its latest answer falls on the current couple-local date, so answering a partner's carried question doesn't make it vanish until the next day. The Questions tab is one list (`DailyChallengeSnapshot.readOverviewQuestions`) sorted by `questionsTabOrder`: a partner question still awaiting the user's answer (`DailyChallengeQuestion.isAwaitingCurrentUserAnswer`) is pinned on top so the actionable cards are never buried, then everything else by `readOverviewOrder` (most recent answer first, via `DailyChallengeQuestion.latestAnswerDate`). The history's within-day order uses `readOverviewOrder` directly. The tab no longer freezes the order or scrolls-to/highlights after answering — answering a partner question reveals the reply inside the cover (`DailyPartnerAnswerFlow`), so it's fine that the card then re-sorts down into the timeline.

## Memories

- `ios/PaeoniaApp/Features/Memories/Timeline/MemoriesScreen.swift`: the Memories tab — local-first timeline of memory cards, empty state, toolbar `+` to create, pull-to-refresh, push navigation to detail, and banner-routed notices. Owns its `MemoriesViewModel` as `@State` and configures it in `.task(id: currentUserID)` (load-bearing key); the active couple id flows through `.onChange` so it never cancels a load.
- `ios/PaeoniaApp/Features/Memories/Timeline/MemoriesViewModel.swift`: `@MainActor @Observable` screen state and all mutations (create, update title/date, upsert own note, attach/remove photos, hide/delete). Talks only to `MemoryDataServicing`; never the repository or Supabase gateway directly. After each local change it flushes through an injected sync handler (wired to `RootViewModel.syncAfterLocalChange` via `MainTabView.onMemoriesLocalChange`) and reloads the cache.
- `ios/PaeoniaApp/Features/Memories/Timeline/MemoryTimeline.swift`: pure day-grouping/ordering (newest day first, newest-created first within a day), visibility filtering (hidden/removed/pending-delete dropped), and `yyyy-MM-dd` couple-local date parse/format helpers. Unit-tested.
- `ios/PaeoniaApp/Features/Memories/Timeline/MemoryCardView.swift`: one memory's timeline card (date, title, photo strip, note preview, subtle "saved on this phone" while dirty). `MemoryDateStyle` holds the shared UTC date format styles.
- `ios/PaeoniaApp/Features/Memories/Editor/MemoryEditorView.swift`: the new-memory form sheet (title + date required, plus a note or at least one photo). `MemoryTextField` is the shared styled multiline field used across the memory sheets.
- `ios/PaeoniaApp/Features/Memories/Detail/MemoryDetailView.swift`: full memory — photo gallery, both partners' notes, edit own note, edit title/date, add/remove own photos, and delete (centered confirmation alert). Re-reads its record by id from the view model, so it reflects edits and dismisses itself once the memory is deleted.
- `ios/PaeoniaApp/Features/Memories/Components/MemoryMediaImageView.swift`: loads/caches a memory photo via the shared `MemoryMediaImageService` (signed `get_media_signed_url` download, on-disk cache keyed by media asset id, separate `MemoryMedia` cache dir). The centralized local privacy purger cancels in-flight downloads and clears derived media when access is hidden; permanent relationship loss or user departure also removes owner-scoped local memory rows and pending writes.
- `ios/PaeoniaAppTests/Memories/MemoryDataLayerTests.swift`: data-layer/sync-stream coverage. `MemoryTimelineTests.swift`: grouping/ordering/visibility/date helpers. `MemoriesViewModelTests.swift`: create (note-only and photo, including upload failure), delete, note upsert, validation, and sync-handler wiring.

Memory photos require an online upload at save time: `MemoryMediaUploading` reserves/uploads/finalizes and returns a real `mediaAssetID`, which the create/attach calls embed as optimistic media. Note-only memories are fully offline/local-first. If any photo upload fails, nothing is saved and the form stays put — content is never partially dropped. Memory thread messages (`createMemoryThreadMessage`) are write-only in the data layer (the snapshot exposes only `threadID`, no message read model), so there is intentionally no thread/conversation UI yet.

## Countdown / Milestones

- `ios/PaeoniaApp/Features/Countdown/Milestones/RelationshipMilestone.swift`: pure milestone schedule. `RelationshipMilestoneCalculator.nextMilestone(startedOn:now:)` parses `couples.started_on` (`yyyy-MM-dd`) and returns the single soonest upcoming `RelationshipMilestone` (`.firstMonth`, `.months`, `.halfYear`, `.firstAnniversary`, `.years`, `.days`) with its date and `daysRemaining`. Months carry the first year, then yearly anniversaries plus round day counts (100, 500, then every 1,000) fill the gaps. No SwiftUI; unit-tested in `RelationshipMilestoneTests.swift`.
- `ios/PaeoniaApp/Features/Countdown/Milestones/RelationshipMilestoneViewModel.swift`: presentation state for the relationship date. It reads the durable pending value before the server snapshot, keeps newer queued edits visible during refresh, and requests sync after an optimistic local save.
- `ios/PaeoniaApp/Features/Countdown/Data/`: local-first relationship-date service, Supabase gateway, and pending-operation handler for `set_couple_started_on`.
- `ios/PaeoniaApp/Features/Countdown/Components/MilestoneCountdownCard.swift` and `RelationshipDateEditorView.swift`: the Us-tab square tile plus honest missing-date setup/edit sheet. The tile derives its number/date/name from `RelationshipMilestoneCalculator`; either partner can set or correct the date, but future dates are rejected. `started_on` flows from `RootViewModel` through `MainTabView`/`PairedHomeView`, and local changes flow back through the shared sync callback. It is never part of a `.task(id:)` key.
- `ios/PaeoniaAppTests/RelationshipMilestoneTests.swift`: schedule coverage across each life stage (new couple, monthly, 100/500/1,000 days, half-year, first/later anniversaries, on-the-day, unparseable date).
- `ios/PaeoniaAppTests/RelationshipStartedOnTests.swift` and `supabase/tests/relationship_started_on_test.sql`: queued local state, partner propagation, timezone-correct validation, authorization, idempotency, stale-sequence protection, and App Review dispatch coverage.

## Pairing, Paywall, And Streak Restore

- `ios/PaeoniaApp/Features/Pairing/Home/PairedHomeView.swift`: paired home surface and high-level home composition.
- `ios/PaeoniaApp/Features/Pairing/Invite/PairingInviteView.swift` and `PairingInviteViewModel.swift`: invite creation/entry flow.
- `ios/PaeoniaApp/Features/Pairing/Celebration/`: pairing celebration view, profile treatment, and particle field.
- `ios/PaeoniaApp/Features/Pairing/Components/PairedProfilesHeader.swift`: reusable paired profile header.
- `ios/PaeoniaApp/Features/Paywall/Offer/PaywallView.swift`, `PaywallContentView.swift`, and `PaywallViewModel.swift`: paywall offer flow, product loading, purchase state, and main layout. Invite entry first previews the inviter/safety flag and cannot accept until the user approves the centered confirmation. Ordinary acceptance leaves `started_on` unset.
- `ios/PaeoniaApp/Features/Paywall/Models/PaywallPresentation.swift`: UI presentation model for honest trial/non-trial pricing, App Store confirmation, renewal timing, and shared-space copy. Paired audiences use the partner name only when it is available.
- `ios/PaeoniaApp/Features/Paywall/Components/`: paywall artwork, billing selector, CTA, footer actions, invite code, scroll cue, and timeline components.
- `ios/PaeoniaApp/Features/StreakRestore/Restore/StreakRestoreView.swift` and `StreakRestoreViewModel.swift`: streak restore purchase flow.
- `ios/PaeoniaApp/Features/StreakRestore/Detail/StreakDetailView.swift`: streak detail presentation.

## Settings, Notifications, And Subscription

- `ios/PaeoniaApp/Features/Settings/SettingsView.swift` and `SettingsViewModel.swift`: paired-user profile, location and notification preferences, StoreKit restore, privacy/safety entry, sign-out, confirmed relationship leave, and confirmed account deletion.
- `ios/PaeoniaApp/Features/Settings/PairedProfileEditorView.swift`: validated paired name/photo editing. A replacement is uploaded and linked before the old private asset is queued for cleanup; removing/replacing an image also invalidates any in-flight old-asset cache write.
- `ios/PaeoniaApp/Features/Settings/SettingsDestinationLinksView.swift`: production support, privacy, and terms destinations shown in paired Settings. Apple subscription management lives in `SettingsView`'s purchases card next to purchase restore.
- `ios/PaeoniaApp/Features/PrivacySafety/`: data access/export/correction requests plus conduct report-and-leave/block UI. `PrivacySafetyService` owns the authenticated RPC/table boundary, view models own validation/deduplication, and Settings supplies the current partner identity.
- `ios/PaeoniaApp/Services/Auth/GoogleSignInService.swift`, `ProviderAvatarImageLoader.swift`, and `SupabaseAuthService.swift`: transient Google provider-avatar import. Only bounded HTTPS image bytes from Google-hosted SDK URLs are accepted; Paeonia stores a distinct private fallback asset ID, never the public provider URL. A user-uploaded override can be removed to reveal this fallback, but the provider fallback itself is not removable in Settings.
- `ios/PaeoniaApp/Services/Notifications/NotificationPreferencesService.swift`: reads and writes the user's server-backed notification preferences.
- `ios/PaeoniaApp/Features/Auth/Permissions/PushPermissionPrimerView.swift` and `ios/PaeoniaApp/Services/Notifications/PushPermissionPrimerStore.swift`: localized one-benefit notification primer and installation-scoped response persistence. "Not now" suppresses future automatic primers on that installation.
- `ios/PaeoniaApp/Services/Notifications/PushAuthorizationService.swift`, `PushRegistrationService.swift`, and `PushRegistrationGate.swift`: system authorization and APNs device registration gating. The authorization service exposes the not-determined state so the primer never appears after iOS already has a choice.
- `ios/PaeoniaApp/Services/Notifications/PaeoniaDeepLink.swift` and `PaeoniaNotificationRouter.swift`: notification payload routing into Daily Challenge, widget drawing, streak, and App Store subscription-management surfaces.
- `supabase/migrations/20260711212432_queue_subscription_trial_reminders.sql`: Tidex-pattern server reminder for verified initial Apple free trials; queues one localized, idempotent push per device two days before trial expiry and routes taps to App Store subscription management.
- `ios/PaeoniaApp/Services/Subscription/PaeoniaStoreKitService.swift`: StoreKit product loading, account-specific introductory-offer eligibility, purchase, restore, and backend transaction verification calls. `PaywallViewModel` does not become presentation-ready until both products and offer eligibility settle, and keeps the last stable offer during refresh.

## Account Lifecycle And Local Privacy

- `ios/PaeoniaApp/App/RootViewModel.swift` and `ios/PaeoniaApp/Services/Auth/`: root-owned sign-out/deletion lifecycle, paired profile updates, and access re-resolution. Account deletion obtains a fresh Apple authorization code when possible, while cancellation still proceeds through the documented manual-revocation fallback.
- `supabase/migrations/20260709232648_finish_account_deletion_workflow.sql`: atomic Paeonia-data deletion boundary, relationship ending, device/location/notification cleanup, profile anonymization, permanent JWT tombstone guards, retryable Auth-user deletion jobs, and operator retry functions.
- `supabase/functions/delete-account/` and `supabase/functions/_shared/appleSignInDeletion.ts`: authenticated deletion worker, global session revocation, Sign in with Apple code exchange/revocation, hard Auth deletion, and secret-protected queue draining. Required production secrets and recovery steps live in `supabase/README.md`.
- `ios/PaeoniaApp/Storage/Privacy/`: centralized, idempotent owner-scoped privacy purge. Temporary entitlement loss hides widget/media/location derivatives while preserving drafts and pending work; permanent relationship loss purges relationship content; sign-out/account deletion remove all owner SwiftData rows, drafts, caches, widget/App Group files, invite credentials, and persisted relationship identifiers.
- `ios/PaeoniaApp/Services/Sync/Streams/RelationshipSyncEventApplier.swift`: maps backend `local_purge_scope` hints to temporary-hide or permanent-purge behavior, treating relationship-end `pending_uploads: review` as permanent for MVP because no recovery UI exists. Purge-driving events require the sync session's current `relationshipCoupleID`; an old relationship event cannot erase a newly paired couple's local state, and unknown relationship identity favors no data loss until Root resolves the access snapshot.
- `ios/PaeoniaAppTests/Sync/LocalPrivacyPurgeTests.swift`, `PaeoniaSyncServiceTests.swift`, and `RelationshipSyncEventsStreamTests.swift`: owner isolation, idempotence, temporary-versus-permanent retention, coordinator wiring, and cross-couple regression coverage.

## Widget Drawing

- `ios/PaeoniaApp/Features/WidgetDrawing/Canvas/WidgetDrawingView.swift`: drawing screen composition.
- `ios/PaeoniaApp/Features/WidgetDrawing/Canvas/WidgetDrawingViewModel.swift`: drawing state, toolbar actions, save/clear flow, and pending sync state.
- `ios/PaeoniaApp/Features/WidgetDrawing/Canvas/WidgetDrawingControlsView.swift`: color, size, and tool controls.
- `ios/PaeoniaApp/Features/WidgetDrawing/Canvas/PencilKitCanvasView.swift`: SwiftUI bridge for PencilKit canvas.
- `ios/PaeoniaApp/Features/WidgetDrawing/Components/HomeWidgetPreview.swift`: in-app widget preview.
- `ios/PaeoniaApp/Features/WidgetDrawing/History/WidgetDrawingHistoryView.swift` and `WidgetDrawingHistoryViewModel.swift`: preserved drawing history.
- `ios/PaeoniaApp/Services/Widget/WidgetDrawingRasterizer.swift`: raster output for widget payloads.
- `ios/PaeoniaApp/Services/Widget/WidgetSharePayload.swift`, `WidgetCanvasService.swift`, and `ios/PaeoniaWidget/PaeoniaWidgetStore.swift`: App Group payload contract and renderer. Payloads default to redacted; only a current-version validated save opts into drawing display, and malformed/redacted/unsafe-path content falls back to the neutral placeholder. MVP supports Home Screen widget families only.
- `ios/PaeoniaAppTests/WidgetDrawingViewModelTests.swift`, `WidgetDrawingHistoryViewModelTests.swift`, `WidgetCanvasServiceTests.swift`, and `WidgetCanvasUploadServiceTests.swift`: focused widget drawing coverage.

MVP drawing payloads are PencilKit-based. Do not replace them with hand-rolled stroke formats unless the product decision changes in `docs/phase-3-data-contract.md`.

## Sync, Access, And Location

- `ios/PaeoniaApp/Services/Sync/PaeoniaSyncService.swift` and `PaeoniaSyncServiceDefaults.swift`: orchestration for local-first sync work.
- `ios/PaeoniaApp/Services/Sync/SyncClientOperation.swift` and `SyncTypes.swift`: queued operation envelope and shared sync types.
- `ios/PaeoniaApp/Services/Sync/Streams/`: individual sync streams for access events, pending operation drain, relationship events, and location visibility.
- `ios/PaeoniaApp/Services/Access/AccessRouteService.swift`, `AccessRoute.swift`, `SupabaseAccessGateway.swift`, and `SupabaseAccessDTOs.swift`: current relationship/access routing.
- `ios/PaeoniaApp/Services/Location/`: foreground location capture, Supabase gateway, models, and pending operation handling.
- `ios/PaeoniaApp/Features/Location/Map/CoupleMapCard.swift`, `LocationMapViewModel.swift`, and `LocationNoticeLocalization.swift`: map card UI and user-facing state. The permission action first explains latest-location-only, foreground-only, no-history behavior. Last-known locations do not expire; after 24 hours the partner marker dims and ordinary text states when it was recorded.
- `ios/PaeoniaAppTests/Sync/`: sync coordinator, local store, operation drain, and relationship/access stream tests.
- `ios/PaeoniaAppTests/Location/LocationFeatureTests.swift`: partner location and visibility behavior.

Do not discard a last-known partner location merely because it is old. Current product intent is latest partner location only, foreground updates only, no location history, a visible 24-hour stale treatment, and a map that appears only after both partners opt in.

## Localization

- `ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings`: ordinary app strings.
- `ios/PaeoniaApp/Resources/Localization/InfoPlist.xcstrings`: system permission copy.
- `scripts/xcstrings-set`: preferred helper for ordinary plain string entries.

Use generated `LocalizedStringResource` symbols in Swift, not raw string keys. Use `./scripts/xcstrings-set` for plain entries so English, Norwegian Bokmal, and translator comments stay consistent.

## Design System

- `ios/PaeoniaApp/Shared/DesignSystem/PaeoniaColors.swift`: semantic color tokens.
- `ios/PaeoniaApp/Shared/DesignSystem/PaeoniaSpacing.swift`: spacing tokens.
- `ios/PaeoniaApp/Shared/DesignSystem/PaeoniaRadius.swift`: corner radius tokens.
- `ios/PaeoniaApp/Shared/DesignSystem/PaeoniaTypography.swift`: typography roles.
- `ios/PaeoniaApp/Shared/DesignSystem/PaeoniaMotion.swift`: animation timing and motion helpers.
- `ios/PaeoniaApp/Shared/DesignSystem/PaeoniaHaptics.swift`: shared haptic patterns.
- `ios/PaeoniaApp/Shared/DesignSystem/Components/PaeoniaButtonStyles.swift`: primary/secondary/destructive button styles.
- `ios/PaeoniaApp/Shared/DesignSystem/Components/PaeoniaCard.swift`: meaningful framed surfaces only.
- `ios/PaeoniaApp/Shared/DesignSystem/Components/PaeoniaTopBanner.swift`: app-level transient errors.
- `ios/PaeoniaApp/Shared/DesignSystem/Components/PaeoniaWordmark.swift`: wordmark and brand lockup treatment.
- `ios/PaeoniaApp/Shared/Components/PaeoniaProfilePhotoAvatar.swift` and `PaeoniaProfileImageCropSheet.swift`: shared profile photo UI.

Prefer these tokens and components over local hardcoded colors, fonts, button shapes, banners, and cards.

## Supabase

- `supabase/README.md`: working rules and common local commands.
- `docs/phase-3-data-contract.md`: source of truth for data-model and privacy decisions.
- `docs/phase-3-migration-checklist.md`: migration order, RLS helpers, table surface classification, and grants.
- `supabase/migrations/`: migration files. Create new files with `supabase migration new <name>`.
- `supabase/functions/`: Edge Functions. Deploy with the Supabase CLI, not MCP deploy tools.
- `supabase/questions/README.md`: question catalog file structure.
- `supabase/questions/system/*`: source-controlled system question content.
- `supabase/functions/apple-verify-purchase/`, `apple-redeem-streak-restore/`, and `apple-server-notifications/`: StoreKit verification, streak-restore redemption, and App Store Server Notification handling.
- `supabase/functions/send-push-notifications/`: APNs outbox drain for alert and background notifications.
- `supabase/functions/cleanup-media-storage/`: trusted media and report-snapshot Storage deletion drain.
- `ios/Scripts/mint-review-codes.mjs` and `revoke-review-codes.mjs`: App Review demo-pair access lifecycle. Codes are operational output and must never be committed.

Most backend changes should start by checking the data contract and migration checklist before inspecting individual SQL files.

## Marketing

- `docs/marketing-app-contract.md`: routes, Universal Links, AASA, Cloudflare headers/redirects, and app-required static files.
- `marketing/app/`: Next.js App Router pages.
- `marketing/app/[locale]/`: localized public pages.
- `marketing/app/(static)/join/page.tsx`: static invite fallback route for `/join/*`.
- `marketing/components/`: shared page components.
- `marketing/lib/i18n/dictionaries/`: localized marketing and legal dictionaries.
- `marketing/lib/paths.ts` and `marketing/lib/metadata.ts`: route and metadata helpers.
- `marketing/public/_headers` and `marketing/public/_redirects`: Cloudflare Pages behavior.
- `marketing/public/.well-known/apple-app-site-association`: Universal Links file when present in the export/public tree.

Do not route Supabase traffic through the marketing app. `paeonia.no` is public web and Universal Links; `api.paeonia.no` is Supabase.
