import SwiftUI

struct PairedHomeView: View {
    let currentUserID: UUID?
    let coupleID: UUID?
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    /// The day the relationship started (`yyyy-MM-dd`), driving the milestone countdown.
    let relationshipStartedOn: String?
    let milestoneIsSaving: Bool
    let onSaveRelationshipStartedOn: (Date) async -> Bool
    let dailyChallengeCardState: DailyChallengeCardState
    let dailyChallengeStreak: StreakPillState
    let zoomNamespace: Namespace.ID?
    let locationMapState: CoupleMapState
    let onPromptCurrentLocation: () -> Void
    var unreadChats: [UnreadChatRow] = []
    var onOpenChat: (UUID) -> Void = { _ in }
    /// Shows a game's card while the partner has the game open, so an invite is one tap away.
    var games: GamesViewModel?
    /// Sends and receives the hearts on the map card.
    var hearts: HeartsViewModel?
    var onOpenGame: (GamesDestination) -> Void = { _ in }
    var onTapStreak: (() -> Void)?
    var onOpenDailyChallenge: () -> Void = {}
    /// Opens the answer flow of a partner question shown as a locked row on the daily card.
    var onOpenPartnerQuestion: (UUID) -> Void = { _ in }
    var onOpenWidgetDrawing: () -> Void = {}
    /// The old question, drawing or memory shown under the daily card. Hidden when there is none.
    var lookBack: LookBackViewModel?
    var onOpenLookBack: (LookBackItem) -> Void = { _ in }
    var onRefresh: () async -> Void = {}
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// iPad landscape: the map with the other cards in two columns below it on the
    /// left, the drawing and milestone tiles stacked on the right (`HomeWideColumnsLayout`).
    @State private var isWideLayout = false
    /// The scroll view's visible height and the cards' height, for `spareSpaceArt`.
    @State private var viewportHeight: CGFloat = 0
    @State private var cardsHeight: CGFloat = 0

    /// The peony spray needs at least this much empty space below the cards to show.
    private static let spareSpaceArtMinHeight: CGFloat = 120
    private static let spareSpaceArtMaxWidth: CGFloat = 500
    private static let alertTypesSeenOnHome: Set<String> = ["widget_updated", "streak_reminder"]

    init(
        currentUserID: UUID? = nil,
        coupleID: UUID? = nil,
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerDisplayName: String?,
        partnerProfilePhotoAssetID: UUID? = nil,
        relationshipStartedOn: String? = nil,
        milestoneIsSaving: Bool = false,
        onSaveRelationshipStartedOn: @escaping (Date) async -> Bool = { _ in false },
        dailyChallengeCardState: DailyChallengeCardState = DailyChallengeCardState(
            kind: .loading,
            answeredCount: 0,
            totalCount: DailyChallengeProgress.requiredOwnQuestionCount
        ),
        dailyChallengeStreak: StreakPillState = .hidden,
        zoomNamespace: Namespace.ID? = nil,
        locationMapState: CoupleMapState,
        onPromptCurrentLocation: @escaping () -> Void = {},
        unreadChats: [UnreadChatRow] = [],
        onOpenChat: @escaping (UUID) -> Void = { _ in },
        games: GamesViewModel? = nil,
        hearts: HeartsViewModel? = nil,
        onOpenGame: @escaping (GamesDestination) -> Void = { _ in },
        onTapStreak: (() -> Void)? = nil,
        onOpenDailyChallenge: @escaping () -> Void = {},
        onOpenPartnerQuestion: @escaping (UUID) -> Void = { _ in },
        onOpenWidgetDrawing: @escaping () -> Void = {},
        lookBack: LookBackViewModel? = nil,
        onOpenLookBack: @escaping (LookBackItem) -> Void = { _ in },
        onRefresh: @escaping () async -> Void = {}
    ) {
        self.currentUserID = currentUserID
        self.coupleID = coupleID
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.relationshipStartedOn = relationshipStartedOn
        self.milestoneIsSaving = milestoneIsSaving
        self.onSaveRelationshipStartedOn = onSaveRelationshipStartedOn
        self.dailyChallengeCardState = dailyChallengeCardState
        self.dailyChallengeStreak = dailyChallengeStreak
        self.zoomNamespace = zoomNamespace
        self.locationMapState = locationMapState
        self.onPromptCurrentLocation = onPromptCurrentLocation
        self.unreadChats = unreadChats
        self.onOpenChat = onOpenChat
        self.games = games
        self.hearts = hearts
        self.onOpenGame = onOpenGame
        self.onTapStreak = onTapStreak
        self.onOpenDailyChallenge = onOpenDailyChallenge
        self.onOpenPartnerQuestion = onOpenPartnerQuestion
        self.onOpenWidgetDrawing = onOpenWidgetDrawing
        self.lookBack = lookBack
        self.onOpenLookBack = onOpenLookBack
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // One layout for phone and wide iPad keeps the cards' identity, so turning
                // the iPad doesn't reset them or close the milestone sheet. The spacing
                // matches the gap inside the milestone/drawing tile row so the cards read
                // as one grid.
                cardsLayout {
                    mainColumn
                    milestoneAndWidget
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space16)
                .paeoniaReadableWidth(
                    isWideLayout ? PaeoniaSpacing.wideContentWidth : PaeoniaSpacing.readableContentWidth
                )
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: unreadChats.isEmpty)
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: games?.partnerGame?.kind)
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: lookBack?.item)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardsHeight = $0 }

                spareSpaceArt
            }
        }
        // The container size already leaves out the bars' content insets.
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
            viewportHeight = height
        }
        .paeoniaWideLayout($isWideLayout)
        .heartsLifecycle(hearts, ownerUserID: currentUserID, partnerName: partnerName)
        .scrollIndicators(.hidden)
        .lookBackRefresh(lookBack, userID: currentUserID, coupleID: coupleID)
        .refreshable {
            await onRefresh()
        }
        // Home shows the couple's current drawing and the streak, so seeing it
        // means the user has noticed a new drawing or a check-in reminder.
        .task {
            await DeliveredNotifications.clear(types: Self.alertTypesSeenOnHome)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await DeliveredNotifications.clear(types: Self.alertTypesSeenOnHome)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the scroll view reach the bottom edge so the tab bar's automatic
        // content inset applies and cards scroll behind the floating glass bar,
        // instead of a flat background panel filling the space above it.
        .background(.paeoniaBackgroundPrimary)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image(.paeoniaMark)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                    .accessibilityHidden(true)
            }
            // The mark is the brand, not a control, so keep it free of the
            // system's Liquid Glass capsule and let it sit flat on the bar.
            .sharedBackgroundVisibility(.hidden)

            // The streak lives at the trailing edge of the bar, sized to match the brand
            // mark and carried in the toolbar's standard background. It fades in when
            // the streak count becomes available rather than popping in abruptly.
            // Reserving a fixed-width placeholder slot in the toolbar is not idiomatic
            // SwiftUI, so we keep the conditional item and rely on an opacity transition
            // instead. Instant under Reduce Motion.
            if dailyChallengeStreak.isVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    DailyStreakToolbarLabel(state: dailyChallengeStreak, onTap: onTapStreak)
                        .transition(.opacity)
                        .animation(
                            reduceMotion ? nil : PaeoniaMotion.stateChange,
                            value: dailyChallengeStreak.isVisible
                        )
                }
            }
        }
    }

    private var mainColumn: some View {
        let layout = isWideLayout
            ? AnyLayout(HomeWideMainCardsLayout(spacing: PaeoniaSpacing.space16))
            : AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
        return layout {
            CoupleMapCard(
                currentName: currentName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                partnerName: partnerName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                state: locationMapState,
                onPromptCurrentLocation: onPromptCurrentLocation,
                hearts: hearts
            )
            if !unreadChats.isEmpty {
                HomeUnreadChatsCard(
                    chats: unreadChats,
                    partnerName: partnerName,
                    partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                    onOpenChat: onOpenChat
                )
                .transition(.opacity)
            }
            // Only the game the partner opened last. Whose turn it is belongs on the Games tab.
            if let games, let game = games.partnerGame,
               let card = game.card(games.cardContext(for: game.kind, isOnHub: false), open: onOpenGame) {
                card
                    .id(game.kind)
                    .transition(.opacity)
            }
            dailyPromptCard
            lookBackCard
        }
    }

    /// An old question, drawing or memory, directly under today's questions.
    @ViewBuilder
    private var lookBackCard: some View {
        if let lookBack, let item = lookBack.item {
            HomeLookBackCard(
                item: item,
                currentUserID: currentUserID,
                partnerName: partnerName,
                thumbnailLoader: lookBack.thumbnailLoader,
                onOpen: { onOpenLookBack(item) }
            )
            .transition(.opacity)
        }
    }

    /// A peony spray in the space left below the cards on a tall screen, such as an
    /// iPad in landscape. It takes exactly that space, so the page still doesn't
    /// scroll, and is left out when the cards fill the screen.
    @ViewBuilder
    private var spareSpaceArt: some View {
        let spareHeight = (viewportHeight - cardsHeight).rounded(.down)
        if spareHeight >= Self.spareSpaceArtMinHeight {
            Image(.homePeonySpray)
                .resizable()
                .accessibilityHidden(true)
                .scaledToFit()
                .frame(maxWidth: Self.spareSpaceArtMaxWidth, maxHeight: spareHeight - 2 * PaeoniaSpacing.space16)
                .frame(maxWidth: .infinity)
                .frame(height: spareHeight)
                .transition(.opacity)
        }
    }

    private var dailyPromptCard: some View {
        DailyPromptCard(
            state: dailyChallengeCardState,
            partnerName: partnerName,
            partnerPhotoAssetID: partnerProfilePhotoAssetID,
            prefersPartnerAnswersWhenComplete: true,
            zoomNamespace: zoomNamespace,
            onAnswer: onOpenDailyChallenge,
            onOpenPartnerQuestion: onOpenPartnerQuestion
        )
        .zoomSource(DailyFlowZoom.home, in: zoomNamespace)
    }

    private var cardsLayout: AnyLayout {
        isWideLayout
            ? AnyLayout(HomeWideColumnsLayout(spacing: PaeoniaSpacing.space16))
            : AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
    }

    private var milestoneAndWidget: some View {
        // One layout keeps the cards' identity, so a text size change doesn't
        // reset them or close the milestone sheet.
        let layout = if isWideLayout {
            AnyLayout(HomeWideTileColumnLayout(spacing: PaeoniaSpacing.space16))
        } else if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
        } else {
            AnyLayout(HStackLayout(alignment: .top, spacing: PaeoniaSpacing.space16))
        }
        return layout {
            milestoneCard
            HomeWidgetCard(
                coupleID: coupleID,
                partnerName: partnerDisplayName?.trimmedNonEmpty,
                onOpen: onOpenWidgetDrawing
            )
        }
    }

    private var milestoneCard: some View {
        MilestoneCountdownCard(
            startedOn: relationshipStartedOn,
            isSaving: milestoneIsSaving,
            onSave: onSaveRelationshipStartedOn
        )
    }

    private var currentName: String {
        currentDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationYouName)
    }

    private var partnerName: String {
        partnerDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationPartnerName)
    }
}

#Preview {
    NavigationStack {
        PairedHomeView(
            currentDisplayName: "Hjalmar",
            partnerDisplayName: "Oda",
            relationshipStartedOn: "2026-01-08",
            locationMapState: .partnerUnknown(.notSharing)
        )
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
