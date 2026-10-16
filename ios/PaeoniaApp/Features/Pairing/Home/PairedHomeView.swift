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
    /// The partners' avatars at the top, with their stories. Nil hides the row.
    var stories: StoriesViewModel?
    var storyPeople: StoryPeople?
    var onRefresh: () async -> Void = {}
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// iPad landscape: three columns that the cards fill left to right and then down,
    /// with a square map (`HomeWideLayout`).
    @State private var isWideLayout = false

    private static let alertTypesSeenOnHome: Set<String> = ["widget_updated", "streak_reminder", "story_posted"]

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
        stories: StoriesViewModel? = nil,
        storyPeople: StoryPeople? = nil,
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
        self.stories = stories
        self.storyPeople = storyPeople
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            // One layout for phone and wide iPad keeps the cards' identity, so turning
            // the iPad doesn't reset them or close the milestone sheet. The spacing
            // matches the gap inside the milestone/drawing tile row so the cards read
            // as one grid. On the phone, today's questions lead and the tiles sit
            // above the map, so a milestone day's celebration plays on screen.
            // The header with the partners' story avatars sits above every card, also on a wide iPad.
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                homeHeader
                cardsLayout {
                    dailyPromptCard
                    unreadChatsCard
                    partnerGameCard
                    milestoneAndWidget
                        .layoutValue(key: HomeWideRole.self, value: .tiles)
                    mapCard
                    lookBackCard
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            // The header starts right under the status bar, where a navigation bar would
            // put the mark and the streak.
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
        // Home shows the couple's current drawing, the streak and the story ring, so
        // seeing it means the user has noticed a new drawing, a check-in reminder or a story.
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
        // In compact width Home draws its own header instead of a navigation bar. The bar
        // took every tap in its band, so the note bubbles that rise into that space
        // couldn't be tapped. In regular width the tab bar sits at the top, in the bar's
        // row, so the bar stays there with the mark and the streak beside the tabs.
        .toolbarVisibility(drawsOwnHeader ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if !drawsOwnHeader {
                barItems
            }
        }
    }

    /// iPhone, which is portrait only, and a narrow iPad window, where the tab bar is at
    /// the bottom and the top row is free.
    private var drawsOwnHeader: Bool {
        horizontalSizeClass != .regular
    }

    @ToolbarContentBuilder
    private var barItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            brandMark(height: Self.barMarkHeight)
        }
        // The mark is the brand, not a control, so keep it free of the
        // system's Liquid Glass capsule and let it sit flat on the bar.
        .sharedBackgroundVisibility(.hidden)

        // Fades in when the streak count becomes available rather than popping in.
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

    private func brandMark(height: CGFloat) -> some View {
        Image(.paeoniaMark)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }

}

/// The cards `body` lays out.
extension PairedHomeView {
    /// The brand mark and the streak at the corners, and both partners with their stories
    /// in the middle. The note bubbles over the avatars rise up beside the mark and the
    /// streak, so the row uses the space a navigation bar would leave empty.
    private var homeHeader: some View {
        ZStack(alignment: .top) {
            if drawsOwnHeader {
                markAndStreakRow
            }

            // The strip's top is the top of a full note bubble, which lines up with the
            // top of the streak pill.
            if let stories, let storyPeople {
                HomeStoriesStrip(viewModel: stories, people: storyPeople)
            }
        }
    }

    private var markAndStreakRow: some View {
        HStack {
            brandMark(height: Self.markHeight)
            Spacer(minLength: 0)
            if dailyChallengeStreak.isVisible {
                DailyStreakToolbarLabel(state: dailyChallengeStreak, onTap: onTapStreak)
                    // The label pads itself for a capsule. This adds what the
                    // toolbar's capsule added, so the pill keeps its old width.
                    .padding(.horizontal, PaeoniaSpacing.space4)
                    .frame(minHeight: Self.headerBarHeight)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    // Fades in once the streak is known instead of popping in.
                    .transition(.opacity)
            }
        }
        .frame(height: Self.headerBarHeight)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: dailyChallengeStreak.isVisible)
    }

    /// The height of a navigation bar's row, so the mark and the streak sit where a bar
    /// would put them.
    private static let headerBarHeight = PaeoniaSpacing.compactButtonHeight
    /// The mark's frame in the navigation bar, which draws it a little smaller.
    private static let barMarkHeight: CGFloat = 28
    /// The size the navigation bar drew the mark at, for the header Home draws itself.
    private static let markHeight: CGFloat = 22

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
            hearts: hearts,
            aspectRatio: isWideLayout ? 1 : 2
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
        // On a wide iPad the pair usually sits under the header, so the drawing goes
        // under the avatars and the calendar to the edge, where it doesn't compete with
        // them. `ForEach` keeps each tile's identity when the order flips.
        let tiles: [HomeTile] = isWideLayout ? [.drawing, .milestone] : [.milestone, .drawing]
        return layout {
            ForEach(tiles, id: \.self) { tile in
                switch tile {
                case .milestone:
                    milestoneCard
                case .drawing:
                    HomeWidgetCard(
                        coupleID: coupleID,
                        partnerName: partnerDisplayName?.trimmedNonEmpty,
                        onOpen: onOpenWidgetDrawing
                    )
                }
            }
        }
    }

    private enum HomeTile {
        case milestone
        case drawing
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
