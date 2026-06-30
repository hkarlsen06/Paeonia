import SwiftUI

/// The native tab bar shown once a couple is paired.
///
/// Tab selection is owned by `RootViewModel` and passed in as a binding. That lets
/// navigation intent — opening the widget drawing screen from the Home Screen
/// widget — select the Home tab and present its destination in one atomic update,
/// so the screen can never open hidden behind another tab.
struct MainTabView: View {
    let currentUserID: UUID?
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
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
    let onOpenWidgetDrawing: () -> Void
    var onHomeRefresh: () async -> Void = {}
    var onDailyChallengeRefresh: () async -> Void = {}
    var onDailyChallengeLocalChange: @MainActor () async -> Void = {}
    let onMemoriesLocalChange: @MainActor @Sendable () async -> Void

    @State private var dailyChallengeViewModel = DailyChallengeViewModel()
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
    /// Streak-restore offer opened from inside the answer flow's completion screen. A
    /// separate binding because a sheet cannot present over its own full-screen cover,
    /// so the in-flow offer is presented from within the cover instead.
    @State private var showStreakRestoreInFlow = false
    /// The Questions-tab single-question partner-answer flow. The tapped question drives
    /// presentation and is the card the cover zooms out of.
    @State private var partnerAnswerQuestion: DailyChallengeQuestion?
    @Namespace private var zoomNamespace
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        currentUserID: UUID?,
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID?,
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
        onOpenWidgetDrawing: @escaping () -> Void,
        onHomeRefresh: @escaping () async -> Void = {},
        onDailyChallengeRefresh: @escaping () async -> Void = {},
        onDailyChallengeLocalChange: @escaping @MainActor () async -> Void = {},
        onMemoriesLocalChange: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
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
        self.onOpenWidgetDrawing = onOpenWidgetDrawing
        self.onHomeRefresh = onHomeRefresh
        self.onDailyChallengeRefresh = onDailyChallengeRefresh
        self.onDailyChallengeLocalChange = onDailyChallengeLocalChange
        self.onMemoriesLocalChange = onMemoriesLocalChange
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(MainTab.allCases) { tab in
                content(for: tab)
                    .tag(tab)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.systemImage)
                        }
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
        // The answer flow is a full-screen cover that zooms out of the card that opened
        // it (covering the floating tab bar). Reduce Motion drops the zoom for the
        // cover's plain cross-fade. The streak-restore offer is presented from within
        // the cover so it can sit over the full-screen flow.
        .fullScreenCover(isPresented: $isAnswerFlowPresented) {
            DailyChallengeAnswerFlow(
                viewModel: dailyChallengeViewModel,
                onClose: closeAnswerFlow,
                onRestore: { showStreakRestoreInFlow = true },
                onOpenPartnerQuestions: openQuestionsTabFromAnswerFlow
            )
            .zoomTransition(dailyFlowSource.zoomSourceID, in: zoomNamespace, enabled: !reduceMotion)
            .sheet(isPresented: $showStreakRestoreInFlow) {
                streakRestoreSheet(isPresented: $showStreakRestoreInFlow)
            }
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
        if dailyChallengeViewModel.streak.isRestorable {
            showStreakRestore = true
        } else {
            showStreakDetail = true
        }
    }

    private func streakRestoreSheet(isPresented: Binding<Bool>) -> some View {
        StreakRestoreView(
            viewModel: StreakRestoreViewModel(
                streak: dailyChallengeViewModel.streak,
                userID: currentUserID?.uuidString,
                onRestored: { _ in await dailyChallengeViewModel.refreshStreak() }
            ),
            onClose: { isPresented.wrappedValue = false }
        )
        .presentationDetents([.large])
        .presentationBackground(.paeoniaSurfacePrimary)
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
                onLocalChange: { @MainActor @Sendable in
                    await syncAfterLocalChange()
                }
            )
        }
    }

    private var homeTab: some View {
        NavigationStack {
            PairedHomeView(
                currentDisplayName: currentDisplayName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                partnerDisplayName: partnerDisplayName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                relationshipStartedOn: relationshipStartedOn,
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
                WidgetDrawingView(authorName: authorName)
            }
        }
    }

    private var questionsTab: some View {
        NavigationStack {
            DailyChallengeScreen(
                viewModel: dailyChallengeViewModel,
                zoomNamespace: zoomNamespace,
                onOpenAnswerFlow: { openAnswerFlow(source: .questions) },
                onTapStreak: openStreakDetails,
                onRefresh: {
                    await refreshDailyChallenge()
                },
                onAnswerPartnerQuestion: openPartnerAnswerFlow
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

    private var youTab: some View {
        NavigationStack {
            SettingsView(locationViewModel: locationViewModel, partnerName: dailyChallengeParticipants.partnerName)
        }
    }
}

#if DEBUG
#Preview {
    MainTabView(
        currentUserID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
        currentDisplayName: "Hjalmar",
        currentProfilePhotoAssetID: nil,
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
