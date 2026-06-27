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
    @State private var isAnswerFlowExpanded = false
    @Namespace private var dailyChallengeMorph

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
            if isAnswerFlowExpanded {
                DailyChallengeAnswerFlow(
                    viewModel: dailyChallengeViewModel,
                    namespace: dailyChallengeMorph,
                    onClose: closeAnswerFlow
                )
                .zIndex(1)
            }
        }
        .tint(.paeoniaAccentPrimary)
        .task(id: dailyChallengeParticipants) {
            dailyChallengeViewModel.setLocalChangeSyncHandler(onDailyChallengeLocalChange)
            await dailyChallengeViewModel.configure(participants: dailyChallengeParticipants)
        }
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
                dailyChallengeMorphNamespace: morphNamespace(for: .home),
                locationMapState: locationMapState,
                onPromptCurrentLocation: {
                    Task { await locationViewModel.promptForCurrentLocation() }
                },
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
                onOpenAnswerFlow: openAnswerFlow
            )
        }
    }

    /// The card only owns the shared morph ids while it is the visible entry point
    /// and the flow is collapsed. Once expanded, both cards release the ids so the
    /// flow becomes their sole owner and the elements travel into it.
    private func morphNamespace(for tab: MainTab) -> Namespace.ID? {
        guard !isAnswerFlowExpanded, selection.wrappedValue == tab else { return nil }
        return dailyChallengeMorph
    }

    /// Today's questions are created lazily, so opening the flow before the couple
    /// has started kicks off that one-time setup; the flow shows a brief loading
    /// state until the questions arrive.
    private func openAnswerFlow() {
        if dailyChallengeViewModel.homeCardState.kind == .noChallenge {
            Task { await dailyChallengeViewModel.startToday() }
        }
        withAnimation(PaeoniaMotion.pairedScreenTransition) {
            isAnswerFlowExpanded = true
        }
    }

    private func closeAnswerFlow() {
        withAnimation(PaeoniaMotion.pairedScreenTransition) {
            isAnswerFlowExpanded = false
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
