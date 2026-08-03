import SwiftUI

/// The native tab bar shown once a couple is paired.
///
/// Tab selection is owned by `RootViewModel` and passed in as a binding. That lets
/// navigation intent — opening the widget drawing screen from the Home Screen
/// widget — select the Home tab and present its destination in one atomic update,
/// so the screen can never open hidden behind another tab.
struct MainTabView: View {
    let tabs: [MainTab]
    let currentUserID: UUID?
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let currentCustomProfilePhotoAssetID: UUID?
    let currentProviderProfilePhotoAssetID: UUID?
    let currentAuthProvider: AuthProvider?
    let partnerUserID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    let authorName: String?
    /// The active couple, needed to create new memories. Cosmetic for the rest of the
    /// tabs, so it must not be part of any load-bearing `.task(id:)` key.
    let coupleID: UUID?
    /// The day the relationship started (`yyyy-MM-dd`), used by the Us-tab milestone
    /// countdown. Display-only, so it never keys a load.
    let relationshipStartedOn: String?
    let locationMapState: CoupleMapState
    let locationViewModel: LocationMapViewModel
    let selection: Binding<MainTab>
    let widgetDrawingPresented: Binding<Bool>
    let deepLink: Binding<PaeoniaDeepLink?>
    let onOpenWidgetDrawing: () -> Void
    var onHomeRefresh: () async -> Void = {}
    var onDailyChallengeRefresh: () async -> Void = {}
    var onDailyChallengeLocalChange: @MainActor () async -> Void = {}
    var onRelationshipStartedOnLocalChange: @MainActor () async -> Void = {}
    let onMemoriesLocalChange: @MainActor @Sendable () async -> Void
    /// Invoked after the user unpairs from the You tab, so the root re-resolves
    /// access and moves them back to the unpaired flow.
    var onLeftRelationship: () -> Void = {}
    /// Invoked when the user logs out from the You tab, so the root ends the session.
    var onLogout: () -> Void = {}
    /// Invoked after the paired Settings confirmation. Auth/session lifecycle
    /// remains rooted rather than being duplicated in the Settings view model.
    var onDeleteAccount: () -> Void = {}
    /// Saves the paired user's canonical profile through the root-owned auth
    /// service so every tab receives the resulting session in one update.
    var onUpdateProfile: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool = { _, _ in false }
    /// Re-resolves entitlement/access after StoreKit has re-confirmed a purchase.
    var onPurchasesRestored: @MainActor @Sendable () async -> Void = {}

    @State private var dailyChallengeViewModel: DailyChallengeViewModel
    @State private var milestoneViewModel: RelationshipMilestoneViewModel
    @State private var memoriesViewModel: MemoriesViewModel
    private let settingsViewModel: SettingsViewModel?
    private let settingsPrivacyService: (any PrivacySafetyServicing)?
    private let settingsPrivacyOperationProvider: (any SyncClientOperationProviding)?
    private let widgetDrawingViewModel: WidgetDrawingViewModel?
    private let widgetHistoryViewModel: WidgetDrawingHistoryViewModel?
    private let widgetHistoryThumbnailLoader: (any WidgetRevisionThumbnailLoading)?
    @State private var isAnswerFlowPresented = false
    /// Which card the daily answer flow should zoom out of (the Home prompt card or the
    /// Questions-tab hero card), so the cover grows from the one the user tapped.
    @State private var dailyFlowSource: DailyFlowSource = .home
    /// Streak-restore offer opened from the streak badge when a lost streak can still
    /// be bought back, outside the answer flow.
    @State private var showStreakRestore = false
    /// Read-only streak detail sheet, opened by tapping the streak badge while the
    /// streak is healthy (nothing to restore).
    @State private var showStreakDetail = false
    /// The Questions-tab single-question partner-answer flow. The tapped question drives
    /// presentation and is the card the cover zooms out of.
    @State private var partnerAnswerQuestion: DailyChallengeQuestion?
    /// Question to scroll to and briefly highlight after a notification deep link.
    @State private var focusedDailyQuestionID: UUID?
    @Namespace private var zoomNamespace
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Which entry card the daily answer flow zooms out of.
    private enum DailyFlowSource {
        case home
        case questions

        var zoomSourceID: String {
            switch self {
            case .home: DailyFlowZoom.home
            case .questions: DailyFlowZoom.questions
            }
        }
    }

    init(
        tabs: [MainTab] = MainTab.allCases,
        currentUserID: UUID?,
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID?,
        currentCustomProfilePhotoAssetID: UUID?,
        currentProviderProfilePhotoAssetID: UUID?,
        currentAuthProvider: AuthProvider? = nil,
        partnerUserID: UUID?,
        partnerDisplayName: String?,
        partnerProfilePhotoAssetID: UUID?,
        authorName: String?,
        coupleID: UUID?,
        relationshipStartedOn: String?,
        locationMapState: CoupleMapState,
        locationViewModel: LocationMapViewModel,
        selection: Binding<MainTab>,
        widgetDrawingPresented: Binding<Bool>,
        deepLink: Binding<PaeoniaDeepLink?> = .constant(nil),
        onOpenWidgetDrawing: @escaping () -> Void,
        onHomeRefresh: @escaping () async -> Void = {},
        onDailyChallengeRefresh: @escaping () async -> Void = {},
        onDailyChallengeLocalChange: @escaping @MainActor () async -> Void = {},
        onRelationshipStartedOnLocalChange: @escaping @MainActor () async -> Void = {},
        onMemoriesLocalChange: @escaping @MainActor @Sendable () async -> Void = {},
        onLeftRelationship: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {},
        onDeleteAccount: @escaping () -> Void = {},
        onUpdateProfile: @escaping @MainActor @Sendable (
            String, AuthProfilePhotoUpdate
        ) async -> Bool = { _, _ in false },
        onPurchasesRestored: @escaping @MainActor @Sendable () async -> Void = {},
        dailyChallengeViewModel: DailyChallengeViewModel? = nil,
        milestoneViewModel: RelationshipMilestoneViewModel? = nil,
        memoriesViewModel: MemoriesViewModel? = nil,
        settingsViewModel: SettingsViewModel? = nil,
        settingsPrivacyService: (any PrivacySafetyServicing)? =
            PrivacySafetyServiceFactory.makeDefault(),
        settingsPrivacyOperationProvider: (any SyncClientOperationProviding)? = nil,
        widgetDrawingViewModel: WidgetDrawingViewModel? = nil,
        widgetHistoryViewModel: WidgetDrawingHistoryViewModel? = nil,
        widgetHistoryThumbnailLoader: (any WidgetRevisionThumbnailLoading)? = nil
    ) {
        self.tabs = tabs
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.currentCustomProfilePhotoAssetID = currentCustomProfilePhotoAssetID
        self.currentProviderProfilePhotoAssetID = currentProviderProfilePhotoAssetID
        self.currentAuthProvider = currentAuthProvider
        self.partnerUserID = partnerUserID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.authorName = authorName
        self.coupleID = coupleID
        self.relationshipStartedOn = relationshipStartedOn
        self.locationMapState = locationMapState
        self.locationViewModel = locationViewModel
        self.selection = selection
        self.widgetDrawingPresented = widgetDrawingPresented
        self.deepLink = deepLink
        self.onOpenWidgetDrawing = onOpenWidgetDrawing
        self.onHomeRefresh = onHomeRefresh
        self.onDailyChallengeRefresh = onDailyChallengeRefresh
        self.onDailyChallengeLocalChange = onDailyChallengeLocalChange
        self.onRelationshipStartedOnLocalChange = onRelationshipStartedOnLocalChange
        self.onMemoriesLocalChange = onMemoriesLocalChange
        self.onLeftRelationship = onLeftRelationship
        self.onLogout = onLogout
        self.onDeleteAccount = onDeleteAccount
        self.onUpdateProfile = onUpdateProfile
        self.onPurchasesRestored = onPurchasesRestored
        _dailyChallengeViewModel = State(
            initialValue: dailyChallengeViewModel ?? DailyChallengeViewModel()
        )
        _milestoneViewModel = State(
            initialValue: milestoneViewModel ?? RelationshipMilestoneViewModel()
        )
        _memoriesViewModel = State(
            initialValue: memoriesViewModel ?? MemoriesViewModel()
        )
        self.settingsViewModel = settingsViewModel
        self.settingsPrivacyService = settingsPrivacyService
        self.settingsPrivacyOperationProvider = settingsPrivacyOperationProvider
        self.widgetDrawingViewModel = widgetDrawingViewModel
        self.widgetHistoryViewModel = widgetHistoryViewModel
        self.widgetHistoryThumbnailLoader = widgetHistoryThumbnailLoader
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(tabs) { tab in
                content(for: tab)
                    .tag(tab)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.systemImage)
                        }
                        .accessibilityIdentifier("mainTab.\(tab.rawValue)")
                    }
            }
        }
        .tint(.paeoniaAccentPrimary)
        // Key the load on the signed-in user alone. The partner id, display names,
        // and profile photos all populate/refresh shortly after launch; if they were
        // in this id, every one of those changes would cancel and restart the task —
        // killing an in-flight question fetch with URLError.cancelled. Cosmetic
        // identity instead flows through refreshParticipants below, which never
        // reloads. See the `.task(id:)` note in AGENTS.md.
        .task(id: currentUserID) {
            dailyChallengeViewModel.setLocalChangeSyncHandler(onDailyChallengeLocalChange)
            await dailyChallengeViewModel.configure(participants: dailyChallengeParticipants)
        }
        .onChange(of: dailyChallengeParticipants) { _, participants in
            dailyChallengeViewModel.refreshParticipants(participants)
        }
        .task(id: currentUserID) {
            milestoneViewModel.setSyncAfterLocalChange(onRelationshipStartedOnLocalChange)
            await milestoneViewModel.configure(
                ownerUserID: currentUserID,
                serverStartedOn: relationshipStartedOn
            )
        }
        .onChange(of: relationshipStartedOn) { _, startedOn in
            milestoneViewModel.refreshServerStartedOn(startedOn)
        }
        .onChange(of: milestoneViewModel.error) { _, error in
            guard let error else { return }
            bannerCenter.show(.error(message: error.message))
            milestoneViewModel.clearError()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await milestoneViewModel.retryPendingChangeIfNeeded() }
            }
        }
        .task(id: deepLink.wrappedValue) {
            await handleDeepLink(deepLink.wrappedValue)
        }
        // The answer flow is a full-screen cover that zooms out of the card that opened
        // it (covering the floating tab bar). Reduce Motion drops the zoom for the
        // cover's plain cross-fade. A slipped streak's completion screen buys the
        // streak back in place (see `makeStreakRestoreViewModel`), rather than opening a
        // second, near-identical restore screen over the cover.
        .fullScreenCover(isPresented: $isAnswerFlowPresented) {
            DailyChallengeAnswerFlow(
                viewModel: dailyChallengeViewModel,
                onClose: closeAnswerFlow,
                makeStreakRestoreViewModel: makeStreakRestoreViewModel,
                onOpenPartnerQuestions: openQuestionsTabFromAnswerFlow
            )
            .zoomTransition(dailyFlowSource.zoomSourceID, in: zoomNamespace, enabled: !reduceMotion)
            .environment(bannerCenter)
        }
        // The single-question partner-answer flow zooms out of the tapped card.
        .fullScreenCover(item: $partnerAnswerQuestion) { question in
            DailyPartnerAnswerFlow(
                question: question,
                viewModel: dailyChallengeViewModel,
                onClose: closePartnerAnswerFlow
            )
            .zoomTransition(question.id, in: zoomNamespace, enabled: !reduceMotion)
            .environment(bannerCenter)
        }
        // The streak badge opens the restore offer (broken) from outside the answer flow.
        .sheet(isPresented: $showStreakRestore) {
            streakRestoreSheet(isPresented: $showStreakRestore)
        }
        // …or the read-only detail sheet when the streak is healthy.
        .sheet(isPresented: $showStreakDetail) {
            StreakDetailView(
                streak: dailyChallengeViewModel.streak,
                onClose: { showStreakDetail = false }
            )
            .presentationDetents([.large])
            .presentationBackground(.paeoniaSurfacePrimary)
        }
    }

    /// The streak chip everywhere it appears: a flame when healthy, a tappable
    /// "broken" chip advertising the lost streak while a restore is on offer.
    private var streakPillState: StreakPillState {
        StreakPillState(dailyChallengeViewModel.streak)
    }

    /// Keep full-screen cover insertion in the same transaction as the native zoom.
    /// Without an explicit transaction, SwiftUI can briefly draw the destination at its
    /// final full-screen size before the zoom animator takes over.
    private var zoomPresentationAnimation: Animation? {
        reduceMotion ? nil : PaeoniaMotion.heroMorph
    }

    /// Tapping the streak badge. A broken streak that can still be bought back opens
    /// the restore offer; an intact streak opens the read-only detail sheet.
    private func openStreakDetails() {
        switch dailyChallengeViewModel.streak.entryDestination {
        case .restore:
            showStreakRestore = true
        case .detail:
            showStreakDetail = true
        }
    }

    private func streakRestoreSheet(isPresented: Binding<Bool>) -> some View {
        StreakRestoreView(
            viewModel: makeStreakRestoreViewModel(),
            onClose: { isPresented.wrappedValue = false }
        )
        .presentationDetents([.large])
        .presentationBackground(.paeoniaSurfacePrimary)
    }

    /// Builds a streak-restore purchase view model bound to the current streak and
    /// signed-in user. Shared by the badge-opened restore sheet and the answer flow's
    /// completion screen, so a restore refreshes the streak whichever path bought it.
    private func makeStreakRestoreViewModel() -> StreakRestoreViewModel {
        StreakRestoreViewModel(
            streak: dailyChallengeViewModel.streak,
            userID: currentUserID?.uuidString,
            onRestored: { _ in await dailyChallengeViewModel.refreshStreak() }
        )
    }

    /// Both partners' identity, used by the daily challenge to label partner-choice
    /// answers. A change of signed-in user reloads; a partner name change just
    /// relabels.
    private var dailyChallengeParticipants: DailyChallengeParticipants {
        DailyChallengeParticipants(
            currentUserID: currentUserID,
            currentDisplayName: currentDisplayName,
            currentProfilePhotoAssetID: currentProfilePhotoAssetID,
            partnerUserID: partnerUserID,
            partnerDisplayName: partnerDisplayName,
            partnerProfilePhotoAssetID: partnerProfilePhotoAssetID
        )
    }

    @ViewBuilder
    private func content(for tab: MainTab) -> some View {
        switch tab {
        case .home:
            homeTab
        case .questions:
            questionsTab
        case .you:
            youTab
        case .memories:
            memoriesTab
        }
    }

    private var memoriesTab: some View {
        let syncAfterLocalChange = onMemoriesLocalChange

        return NavigationStack {
            MemoriesScreen(
                currentUserID: currentUserID,
                coupleID: coupleID,
                viewModel: memoriesViewModel,
                onLocalChange: { @MainActor @Sendable in
                    await syncAfterLocalChange()
                }
            )
        }
    }

    private var homeTab: some View {
        NavigationStack {
            PairedHomeView(
                currentUserID: currentUserID,
                currentDisplayName: currentDisplayName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                partnerDisplayName: partnerDisplayName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                relationshipStartedOn: milestoneViewModel.startedOn,
                milestoneIsSaving: milestoneViewModel.isSaving,
                onSaveRelationshipStartedOn: { date in
                    await milestoneViewModel.save(startedOn: date)
                },
                dailyChallengeCardState: dailyChallengeViewModel.homeCardState,
                dailyChallengeStreak: streakPillState,
                zoomNamespace: zoomNamespace,
                locationMapState: locationMapState,
                onPromptCurrentLocation: {
                    Task { await locationViewModel.promptForCurrentLocation() }
                },
                onTapStreak: openStreakDetails,
                onOpenDailyChallenge: openDailyChallengeFromHome,
                onOpenWidgetDrawing: onOpenWidgetDrawing,
                onRefresh: {
                    await refreshDailyChallenge()
                    await onHomeRefresh()
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            // The brand mark and couple avatars are populated into the navigation
            // bar from inside PairedHomeView, where the name/photo data lives.
            .navigationDestination(isPresented: widgetDrawingPresented) {
                WidgetDrawingView(
                    ownerUserID: currentUserID,
                    authorName: authorName,
                    viewModel: widgetDrawingViewModel,
                    historyViewModel: widgetHistoryViewModel,
                    historyThumbnailLoader: widgetHistoryThumbnailLoader
                )
            }
        }
    }

    private var questionsTab: some View {
        NavigationStack {
            DailyChallengeScreen(
                viewModel: dailyChallengeViewModel,
                zoomNamespace: zoomNamespace,
                focusedQuestionID: $focusedDailyQuestionID,
                onOpenAnswerFlow: { openAnswerFlow(source: .questions) },
                onTapStreak: openStreakDetails,
                onRefresh: {
                    await refreshDailyChallenge()
                },
                onAnswerPartnerQuestion: openPartnerAnswerFlow,
                privacySafetyService: settingsPrivacyService,
                privacyOperationProvider: settingsPrivacyOperationProvider,
                onReportedAndLeft: onLeftRelationship
            )
        }
    }

    /// Keep the daily challenge refresh visually responsive. Read the challenge first
    /// so partner answers and day rollover appear without waiting for broader app sync,
    /// then sync and read once more in case that sync flushed a queued local answer.
    private func refreshDailyChallenge() async {
        await dailyChallengeViewModel.reload()
        await onDailyChallengeRefresh()
        await dailyChallengeViewModel.reload()
    }

    private func openDailyChallengeFromHome() {
        let state = dailyChallengeViewModel.homeCardState
        if state.kind == .complete, state.hasPartnerAnswersForToday {
            selection.wrappedValue = .questions
            return
        }

        openAnswerFlow(source: .home)
    }

    /// Today's questions are created lazily, so opening the flow before the couple
    /// has started kicks off that one-time setup; the flow shows a brief loading
    /// state until the questions arrive.
    private func openAnswerFlow(source: DailyFlowSource) {
        if dailyChallengeViewModel.homeCardState.kind == .noChallenge {
            Task { await dailyChallengeViewModel.startToday() }
        }
        withAnimation(zoomPresentationAnimation) {
            dailyFlowSource = source
            isAnswerFlowPresented = true
        }
    }

    private func openQuestionsTabFromAnswerFlow() {
        selection.wrappedValue = .questions
        isAnswerFlowPresented = false
    }

    private func closeAnswerFlow() {
        isAnswerFlowPresented = false
    }

    private func openPartnerAnswerFlow(_ question: DailyChallengeQuestion) {
        withAnimation(zoomPresentationAnimation) {
            partnerAnswerQuestion = question
        }
    }

    private func closePartnerAnswerFlow() {
        partnerAnswerQuestion = nil
    }

    @MainActor
    private func handleDeepLink(_ deepLink: PaeoniaDeepLink?) async {
        guard let deepLink else {
            return
        }

        switch deepLink {
        case .widgetDrawing:
            onOpenWidgetDrawing()
            self.deepLink.wrappedValue = nil
        case .widgetRefresh:
            // RootView owns the host-app sync and consumes this route once the
            // refresh has settled. Do not race it from the tab hierarchy.
            break
        case .dailyReveal(let instanceID, _):
            selection.wrappedValue = .questions
            await refreshDailyChallenge()
            focusedDailyQuestionID = instanceID
            self.deepLink.wrappedValue = nil
        case .dailyToday:
            selection.wrappedValue = .questions
            await refreshDailyChallenge()
            if dailyChallengeViewModel.homeCardState.kind != .complete {
                openAnswerFlow(source: .questions)
            }
            self.deepLink.wrappedValue = nil
        case .memories:
            selection.wrappedValue = .memories
            await memoriesViewModel.refresh()
            guard !Task.isCancelled, self.deepLink.wrappedValue == deepLink else {
                return
            }
            self.deepLink.wrappedValue = nil
        case .streak:
            selection.wrappedValue = .home
            // The streak may have advanced, broken, or passed its restore deadline
            // since the notification was queued. Refresh before choosing the one
            // destination so a broken streak opens the purchase offer directly.
            await refreshDailyChallenge()
            guard !Task.isCancelled, self.deepLink.wrappedValue == deepLink else {
                return
            }
            openStreakDetails()
            self.deepLink.wrappedValue = nil
        case .subscription:
            // RootView owns this external URL and consumes the binding after it
            // opens App Store subscription management. Leaving it untouched here
            // prevents the paired tab task from racing the root task.
            break
        }
    }

    private var youTab: some View {
        NavigationStack {
            SettingsView(
                viewModel: settingsViewModel,
                currentUserID: currentUserID,
                currentDisplayName: currentDisplayName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                currentCustomProfilePhotoAssetID: currentCustomProfilePhotoAssetID,
                currentProviderProfilePhotoAssetID: currentProviderProfilePhotoAssetID,
                currentAuthProvider: currentAuthProvider,
                partnerUserID: partnerUserID,
                relationshipStartedOn: milestoneViewModel.startedOn,
                milestoneIsSaving: milestoneViewModel.isSaving,
                onSaveRelationshipStartedOn: { date in
                    await milestoneViewModel.save(startedOn: date)
                },
                locationViewModel: locationViewModel,
                partnerName: dailyChallengeParticipants.partnerName,
                onLeftRelationship: onLeftRelationship,
                onLogout: onLogout,
                onDeleteAccount: onDeleteAccount,
                onUpdateProfile: { [onUpdateProfile] displayName, photoUpdate in
                    await onUpdateProfile(displayName, photoUpdate)
                },
                onPurchasesRestored: { [onPurchasesRestored] in
                    await onPurchasesRestored()
                },
                privacySafetyService: settingsPrivacyService,
                privacyOperationProvider: settingsPrivacyOperationProvider
            )
        }
    }
}

#if DEBUG
#Preview {
    MainTabView(
        currentUserID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
        currentDisplayName: "Hjalmar",
        currentProfilePhotoAssetID: nil,
        currentCustomProfilePhotoAssetID: nil,
        currentProviderProfilePhotoAssetID: nil,
        partnerUserID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
        partnerDisplayName: "Oda",
        partnerProfilePhotoAssetID: nil,
        authorName: "Hjalmar",
        coupleID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
        relationshipStartedOn: "2026-01-08",
        locationMapState: .partnerUnknown(.notSharing),
        locationViewModel: LocationMapViewModel(),
        selection: .constant(.home),
        widgetDrawingPresented: .constant(false),
        onOpenWidgetDrawing: {}
    )
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
