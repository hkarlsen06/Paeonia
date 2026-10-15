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
    /// The couple's countdowns and birthdays, shown on the milestone tile and its timeline.
    var coupleDates: CoupleDatesViewModel?
    var coupleDateNames = CoupleDateNames()
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
    /// iPad landscape: three columns, with the map and the tile row under it on the
    /// left two and the cards filling in from the right (`HomeWideLayout`).
    @State private var isWideLayout = false

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
        coupleDates: CoupleDatesViewModel? = nil,
        coupleDateNames: CoupleDateNames = CoupleDateNames(),
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
        self.coupleDates = coupleDates
        self.coupleDateNames = coupleDateNames
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
            // One layout for phone and wide iPad keeps the cards' identity, so turning
            // the iPad doesn't reset them or close the milestone sheet. The spacing
            // matches the gap inside the milestone/drawing tile row so the cards read
            // as one grid. On the phone, today's questions lead and the tiles sit
            // above the map, so a milestone day's celebration plays on screen.
            cardsLayout {
                dailyPromptCard
                unreadChatsCard
                partnerGameCard
                milestoneAndWidget
                    .layoutValue(key: HomeWideRole.self, value: .tiles)
                mapCard
                    .layoutValue(key: HomeWideRole.self, value: .map)
                lookBackCard
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
            // The daily card is tall until today's questions are done, then a short row.
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: dailyChallengeCardState.kind)
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
        // instead of a flat background panel filling the space above it. The light
        // stays put while the cards scroll over it, so a pull to refresh never
        // reveals a plain strip above it.
        .paeoniaTabBackdrop()
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

}

/// The cards `body` lays out.
extension PairedHomeView {
    @ViewBuilder
    private var unreadChatsCard: some View {
        if !unreadChats.isEmpty {
            HomeUnreadChatsCard(
                chats: unreadChats,
                partnerName: partnerName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                onOpenChat: onOpenChat
            )
            .transition(.opacity)
        }
    }

    /// Only the game the partner opened last. Whose turn it is belongs on the Games tab.
    @ViewBuilder
    private var partnerGameCard: some View {
        if let games, let game = games.partnerGame,
           let card = game.card(games.cardContext(for: game.kind, isOnHub: false), open: onOpenGame) {
            card
                .id(game.kind)
                .transition(.opacity)
        }
    }

    private var mapCard: some View {
        CoupleMapCard(
            currentName: currentName,
            currentProfilePhotoAssetID: currentProfilePhotoAssetID,
            partnerName: partnerName,
            partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
            state: locationMapState,
            onPromptCurrentLocation: onPromptCurrentLocation,
            hearts: hearts
        )
    }

    /// An old question, drawing or memory, below the map.
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
            ? AnyLayout(HomeWideLayout(spacing: PaeoniaSpacing.space16))
            : AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
    }

    private var milestoneAndWidget: some View {
        // One layout keeps the cards' identity, so a text size change doesn't
        // reset them or close the milestone sheet. On a wide iPad each tile is a
        // column wide, so they stay side by side at every text size.
        let layout = if dynamicTypeSize.isAccessibilitySize && !isWideLayout {
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
            onSave: onSaveRelationshipStartedOn,
            coupleDates: coupleDates,
            names: coupleDateNames
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
