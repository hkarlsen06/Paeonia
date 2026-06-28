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
    let locationMapState: CoupleMapState
    let locationViewModel: LocationMapViewModel
    let selection: Binding<MainTab>
    let widgetDrawingPresented: Binding<Bool>
    let onOpenWidgetDrawing: () -> Void
    var onHomeRefresh: () async -> Void = {}
    var onDailyChallengeLocalChange: @MainActor () async -> Void = {}

    @State private var dailyChallengeViewModel = DailyChallengeViewModel()
    /// `presented` keeps the flow mounted; `expanded` drives the open/close morph.
    /// They differ only briefly during a close, while the flow plays its collapse.
    @State private var isAnswerFlowPresented = false
    @State private var isAnswerFlowExpanded = false
    @State private var showStreakRestore = false
    @Namespace private var dailyChallengeMorph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        currentUserID: UUID?,
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID?,
        partnerUserID: UUID?,
        partnerDisplayName: String?,
        partnerProfilePhotoAssetID: UUID?,
        authorName: String?,
        locationMapState: CoupleMapState,
        locationViewModel: LocationMapViewModel,
        selection: Binding<MainTab>,
        widgetDrawingPresented: Binding<Bool>,
        onOpenWidgetDrawing: @escaping () -> Void,
        onHomeRefresh: @escaping () async -> Void = {},
        onDailyChallengeLocalChange: @escaping @MainActor () async -> Void = {}
    ) {
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerUserID = partnerUserID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.authorName = authorName
        self.locationMapState = locationMapState
        self.locationViewModel = locationViewModel
        self.selection = selection
        self.widgetDrawingPresented = widgetDrawingPresented
        self.onOpenWidgetDrawing = onOpenWidgetDrawing
        self.onHomeRefresh = onHomeRefresh
        self.onDailyChallengeLocalChange = onDailyChallengeLocalChange
    }

    var body: some View {
        ZStack {
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

            // The answering flow lives above the tab bar so the card can grow into
            // a full-screen surface (and the floating tab bar doesn't show through).
            // Mount (`presented`) and open (`expanded`) are separate so that on close
            // the flow stays mounted long enough to play its reveal-collapse while the
            // elements glide home, then unmounts once it's invisible.
            if isAnswerFlowPresented {
                DailyChallengeAnswerFlow(
                    viewModel: dailyChallengeViewModel,
                    namespace: flowNamespace,
                    isExpanded: isAnswerFlowExpanded,
                    onClose: closeAnswerFlow,
                    onRestore: openStreakRestore
                )
                .zIndex(1)
                .transition(answerFlowTransition)
            }
        }
        .tint(.paeoniaAccentPrimary)
        .task(id: dailyChallengeParticipants) {
            dailyChallengeViewModel.setLocalChangeSyncHandler(onDailyChallengeLocalChange)
            await dailyChallengeViewModel.configure(participants: dailyChallengeParticipants)
        }
        .sheet(isPresented: $showStreakRestore) {
            streakRestoreSheet
        }
    }

    /// The streak chip everywhere it appears: a flame when healthy, a tappable
    /// "broken" chip advertising the lost streak while a restore is on offer.
    private var streakPillState: StreakPillState {
        StreakPillState(dailyChallengeViewModel.streak)
    }

    private func openStreakRestore() {
        showStreakRestore = true
    }

    private var streakRestoreSheet: some View {
        StreakRestoreView(
            viewModel: StreakRestoreViewModel(
                streak: dailyChallengeViewModel.streak,
                userID: currentUserID?.uuidString,
                onRestored: { _ in await dailyChallengeViewModel.refreshStreak() }
            ),
            onClose: { showStreakRestore = false }
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
            placeholderTab(title: tab.title, systemImage: tab.systemImage)
        }
    }

    private var homeTab: some View {
        NavigationStack {
            PairedHomeView(
                currentDisplayName: currentDisplayName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                partnerDisplayName: partnerDisplayName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                dailyChallengeCardState: dailyChallengeViewModel.homeCardState,
                dailyChallengeStreak: streakPillState,
                dailyChallengeMorphNamespace: morphNamespace(for: .home),
                locationMapState: locationMapState,
                onPromptCurrentLocation: {
                    Task { await locationViewModel.promptForCurrentLocation() }
                },
                onTapStreak: openStreakRestore,
                onOpenDailyChallenge: openAnswerFlow,
                onOpenWidgetDrawing: onOpenWidgetDrawing,
                onRefresh: {
                    await dailyChallengeViewModel.reload()
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
                morphNamespace: morphNamespace(for: .questions),
                onOpenAnswerFlow: openAnswerFlow,
                onTapStreak: openStreakRestore
            )
        }
    }

    /// The card only owns the shared morph ids while it is the visible entry point
    /// and the flow is collapsed. While expanding (or collapsing) the card releases
    /// the ids so the flow's elements travel; the card reclaims them as the flow
    /// collapses so they glide back home. Reduce Motion opts out of the glide
    /// entirely (a plain cross-fade is used instead).
    private func morphNamespace(for tab: MainTab) -> Namespace.ID? {
        guard !reduceMotion, !isAnswerFlowExpanded, selection.wrappedValue == tab else { return nil }
        return dailyChallengeMorph
    }

    /// The flow owns the morph ids only while it is open. It releases them the moment
    /// a close begins (so the card can reclaim them and glide the elements back), and
    /// never claims them under Reduce Motion.
    private var flowNamespace: Namespace.ID? {
        (reduceMotion || !isAnswerFlowExpanded) ? nil : dailyChallengeMorph
    }

    /// How the answering flow enters and leaves.
    ///
    /// Under motion the flow uses `.identity`: it never fades as a whole. Its own
    /// surface, content reveal, and element glide all animate from inside the flow
    /// (and it only unmounts once already invisible), so the card reads as growing
    /// and shrinking rather than the screen dissolving over it. Reduce Motion drops
    /// the glide for a plain cross-fade in both directions.
    private var answerFlowTransition: AnyTransition {
        reduceMotion ? .opacity : .identity
    }

    /// Spring that carries the morph. A plain, short cross-fade replaces it under
    /// Reduce Motion.
    private var morphAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: PaeoniaMotion.motionDefault) : PaeoniaMotion.heroMorph
    }

    /// Today's questions are created lazily, so opening the flow before the couple
    /// has started kicks off that one-time setup; the flow shows a brief loading
    /// state until the questions arrive.
    private func openAnswerFlow() {
        if dailyChallengeViewModel.homeCardState.kind == .noChallenge {
            Task { await dailyChallengeViewModel.startToday() }
        }
        // Mount and open together so the flow appears already expanded — the elements
        // glide from the card and the surface wipes open, with no intermediate frame.
        withAnimation(morphAnimation) {
            isAnswerFlowPresented = true
            isAnswerFlowExpanded = true
        }
    }

    private func closeAnswerFlow() {
        guard !reduceMotion else {
            // No glide to wait for: cross-fade the whole flow out and unmount at once.
            withAnimation(morphAnimation) {
                isAnswerFlowExpanded = false
                isAnswerFlowPresented = false
            }
            return
        }
        // Begin the collapse now (the flow wipes shut and the elements glide home),
        // then unmount once the spring settles — unless the user reopened meanwhile.
        withAnimation(morphAnimation) {
            isAnswerFlowExpanded = false
        } completion: {
            if !isAnswerFlowExpanded { isAnswerFlowPresented = false }
        }
    }

    private var youTab: some View {
        NavigationStack {
            SettingsView(locationViewModel: locationViewModel)
        }
    }

    private func placeholderTab(
        title: LocalizedStringResource,
        systemImage: String
    ) -> some View {
        NavigationStack {
            PaeoniaEmptyStateView(
                title: title,
                message: .mainTabPlaceholderMessage,
                systemImage: systemImage
            )
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.paeoniaBackgroundPrimary)
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
        locationMapState: .partnerUnknown(.notSharing),
        locationViewModel: LocationMapViewModel(),
        selection: .constant(.home),
        widgetDrawingPresented: .constant(false),
        onOpenWidgetDrawing: {}
    )
    .preferredColorScheme(.dark)
}
#endif
