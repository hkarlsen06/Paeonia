# Implementation Map

This is the first stop when an agent needs to find the current owner of a Paeonia behavior. Keep this file factual and source-oriented; durable rules still belong in `AGENTS.md`.

## Launch, Root State, And Navigation

- `ios/PaeoniaApp/App/RootView.swift`: root loading surface, top banner mounting, and first app surface switching.
- `ios/PaeoniaApp/App/RootViewModel.swift`: launch-adjacent auth/access/pairing state and `PresentationReadinessProviding` readiness.
- `ios/PaeoniaApp/App/MainTabView.swift` and `ios/PaeoniaApp/App/MainTab.swift`: tab layout and high-level feature entry points.
- `ios/PaeoniaApp/App/RootNoticeLocalization.swift`: root-level user-facing notice copy.
- `ios/PaeoniaAppTests/AccessRouteResolverTests.swift`: access route behavior around launch and relationship access.

When a launch-time network call is cancelled with `NSURLErrorCancelled` / `URLError.cancelled` shortly after render, inspect `.task(id:)` keys before hiding the error. The known Daily Challenge case is documented in `AGENTS.md`.

## Daily Challenge

- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeView.swift`: screen composition, loading hooks, and presentation flow.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeViewModel.swift`: screen state, participant refresh, loading, answering, and reveal coordination.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeService.swift`: Supabase calls for challenge/day/question/answer behavior.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeModels.swift`: UI/domain models and answer-kind shape.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeRemoteRows.swift`: DTOs matching Supabase RPC/read-model rows.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeAnswerFlow.swift`: answering flow and text/photo/voice/partner-choice composition.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyPartnerAnswerFlow.swift`: answering one partner-authored question. On send it holds (`awaitAnswerReveal`) and then turns the cover over to the revealed exchange (partner's reply on top) instead of closing — so the reward doesn't depend on finding the card in the list afterward. Offline/queued sends just close and reveal later on the card.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeQuestionViews.swift`: reusable question and answer UI pieces.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeReadCard.swift`: the shared read-only question card (prompt + status + revealed answers), used by the Questions tab's single read list and the history flow. `DailyChallengeQuestion.list` (in `DailyChallengeModels.swift`) is the shared row→question mapping behind both today's snapshot and history. The Questions tab shows the partner's and the user's questions in one list (`DailyChallengeSnapshot.readOverviewQuestions`), not split into "their"/"mine" sections.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeHistory.swift`: pure date-grouping for the history overview (`DailyChallengeHistoryDay`, newest-day-first grouping, local-date parsing).
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeHistoryViewModel.swift`: history load/state/readiness, banner-routed reload errors. `ViewState.content` carries `Content { pendingPartnerQuestions, days }`; the partner's still-unanswered questions are read live from the daily-challenge snapshot (`answerablePartnerQuestions`, injected via the `pendingPartnerQuestions` closure from `DailyChallengeViewModel.makeHistoryViewModel()`), not from the answered-history RPC, and are deduped against the loaded history.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeHistoryView.swift`: the History full-screen cover — title, close, a top "waiting for you" section of answerable partner cards (same CTA as the Questions tab, gated by `hasCompletedRequiredDailyQuestions`, zooms into `DailyPartnerAnswerFlow` and reloads on close), then centered date dividers + read cards, plus empty/loading/error states. Needs the shared `DailyChallengeViewModel`. Opened from the Questions-tab toolbar History button in `DailyChallengeView.swift`.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeMediaViews.swift`: image/media display for answers.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyVoiceAnswerViews.swift`, `DailyVoiceRecorder.swift`, and `DailyVoiceAudioSession.swift`: voice recording/playback UI and audio session handling.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeDraftStore.swift`: local answer draft persistence.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengeSnapshotCache.swift`: local-first cold-launch cache. The live service writes the raw `DailyChallengeRemoteSnapshotRow` (keyed per user) on every successful snapshot load; `DailyChallengeViewModel.configure` seeds `snapshot`+`streak` from it via `DailyChallengeRemoteSnapshotRow.loadResult` before the network `reload()`, so returning users see real content (not placeholders) on the first frame. Cleared on un-pair in `RootView.clearWidgetIfNeeded` for privacy.
- `ios/PaeoniaApp/Features/DailyChallenge/DailyChallengePendingOperationHandler.swift`: local-first retry handling for queued challenge writes.
- `ios/PaeoniaApp/Services/Media/DailyAnswerMediaDraftStore.swift`, `DailyAnswerMediaUploadService.swift`, and `DailyAnswerMediaImageService.swift`: photo/voice draft storage, upload, and display support.
- `ios/PaeoniaAppTests/DailyChallengeTests.swift`: main regression suite for question state, answer flow, reveal behavior, cancellation, and media handling.

Question content is authored in `supabase/questions/`; read `docs/couple-question-guidelines.md` before changing prompts. For combined `text` + `photo` or `text` + `partner_choice` questions, both composers can be shown at once and each part is optional.

Questions history reads through `public.get_daily_questions_history()` and `public.get_daily_answer_history_details()` (migration `20260628234249_add_daily_questions_history_rpcs.sql`): thin public wrappers over security-definer internal implementations, scoped to instances the viewer has answered, reusing the existing per-answer reveal rules.

A daily question belongs to the couple-local day of its *latest* answer, not its seed day (migration `20260629004244_place_daily_questions_in_latest_answer_day.sql`). `get_daily_questions_history` returns `effective_local_date` (the latest answer's date in the couple's anchor timezone) and `DailyChallengeHistory.grouped` buckets on it; `get_today_daily_questions` keeps a carried-over instance in the Questions tab while its latest answer falls on the current couple-local date, so answering a partner's carried question doesn't make it vanish until the next day. The Questions tab is one list (`DailyChallengeSnapshot.readOverviewQuestions`) sorted by `questionsTabOrder`: a partner question still awaiting the user's answer (`DailyChallengeQuestion.isAwaitingCurrentUserAnswer`) is pinned on top so the actionable cards are never buried, then everything else by `readOverviewOrder` (most recent answer first, via `DailyChallengeQuestion.latestAnswerDate`). The history's within-day order uses `readOverviewOrder` directly. The tab no longer freezes the order or scrolls-to/highlights after answering — answering a partner question reveals the reply inside the cover (`DailyPartnerAnswerFlow`), so it's fine that the card then re-sorts down into the timeline.

## Widget Drawing

- `ios/PaeoniaApp/Features/WidgetDrawing/WidgetDrawingView.swift`: drawing screen composition.
- `ios/PaeoniaApp/Features/WidgetDrawing/WidgetDrawingViewModel.swift`: drawing state, toolbar actions, save/clear flow, and pending sync state.
- `ios/PaeoniaApp/Features/WidgetDrawing/WidgetDrawingControlsView.swift`: color, size, and tool controls.
- `ios/PaeoniaApp/Features/WidgetDrawing/PencilKitCanvasView.swift`: SwiftUI bridge for PencilKit canvas.
- `ios/PaeoniaApp/Features/WidgetDrawing/HomeWidgetPreview.swift`: in-app widget preview.
- `ios/PaeoniaApp/Features/WidgetDrawing/WidgetDrawingHistoryView.swift` and `WidgetDrawingHistoryViewModel.swift`: preserved drawing history.
- `ios/PaeoniaApp/Services/Widget/WidgetDrawingRasterizer.swift`: raster output for widget payloads.
- `ios/PaeoniaAppTests/WidgetDrawingViewModelTests.swift`, `WidgetDrawingHistoryViewModelTests.swift`, `WidgetCanvasServiceTests.swift`, and `WidgetCanvasUploadServiceTests.swift`: focused widget drawing coverage.

MVP drawing payloads are PencilKit-based. Do not replace them with hand-rolled stroke formats unless the product decision changes in `docs/phase-3-data-contract.md`.

## Sync, Access, And Location

- `ios/PaeoniaApp/Services/Sync/PaeoniaSyncService.swift` and `PaeoniaSyncServiceDefaults.swift`: orchestration for local-first sync work.
- `ios/PaeoniaApp/Services/Sync/SyncClientOperation.swift` and `SyncTypes.swift`: queued operation envelope and shared sync types.
- `ios/PaeoniaApp/Services/Sync/Streams/`: individual sync streams for access events, pending operation drain, relationship events, and location visibility.
- `ios/PaeoniaApp/Services/Access/AccessRouteService.swift`, `AccessRoute.swift`, `SupabaseAccessGateway.swift`, and `SupabaseAccessDTOs.swift`: current relationship/access routing.
- `ios/PaeoniaApp/Services/Location/`: foreground location capture, Supabase gateway, models, and pending operation handling.
- `ios/PaeoniaApp/Features/Location/CoupleMapCard.swift`, `LocationMapViewModel.swift`, and `LocationNoticeLocalization.swift`: map card UI and user-facing state.
- `ios/PaeoniaAppTests/Sync/`: sync coordinator, local store, operation drain, and relationship/access stream tests.
- `ios/PaeoniaAppTests/Location/LocationFeatureTests.swift`: partner location and visibility behavior.

Do not treat partner location as unknown until the documented visibility/age threshold says it is unknown. Current product intent is latest partner location only, foreground updates only, and map visible only after both partners opt in.

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
