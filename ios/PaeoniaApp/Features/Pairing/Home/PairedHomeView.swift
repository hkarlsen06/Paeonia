import SwiftUI

struct PairedHomeView: View {
    let currentUserID: UUID?
    let coupleID: UUID?
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    /// Shown above the cards before access ends (`AccessNotice`). Nil hides it.
    let accessNotice: AccessNotice?
    /// The day the relationship started (`yyyy-MM-dd`), driving the milestone countdown.
    let relationshipStartedOn: String?
    let milestoneIsSaving: Bool
    let milestoneIsLoading: Bool
    let onSaveRelationshipStartedOn: (Date) async -> Bool
    /// The couple's countdowns and birthdays, shown on the milestone tile and its timeline.
    var coupleDates: CoupleDatesViewModel?
    var coupleDateNames = CoupleDateNames()
    let dailyChallengeCardState: DailyChallengeCardState
    let dailyChallengeStreak: StreakPillState
    let zoomNamespace: Namespace.ID?
    let locationMapState: CoupleMapState
    /// Whether OpenFreeMap can draw the map header. While it can't, Home shows the map card.
    let mapTiles: HomeMapTileStatus
    let onPromptCurrentLocation: () -> Void
    let onPauseLocationSharing: ((Date) -> Void)?
    var unreadChats: [UnreadChatRow] = []
    var onOpenChat: (UUID) -> Void = { _ in }
    /// Shows a game's card while the partner has the game open, so an invite is one tap away.
    var games: GamesViewModel?
    /// Sends and receives the hearts on the map card.
    var hearts: HeartsViewModel?
    var onOpenGame: (GamesDestination) -> Void = { _ in }
    var onTapStreak: (() -> Void)?
    var onOpenDailyChallenge: () -> Void = {}
    /// Opens the answer flow of an earlier question shown as a locked row on the daily card.
    var onOpenPartnerQuestion: (UUID) -> Void = { _ in }
    /// "Things to try together" after the first day. Nil hides the card.
    var firstSteps: HomeFirstSteps?
    var onOpenFirstStep: (HomeFirstStep) -> Void = { _ in }
    var onCloseFirstSteps: () -> Void = {}
    var onOpenWidgetDrawing: () -> Void = {}
    /// The old question, drawing or memory shown under the daily card. Hidden when there is none.
    var lookBack: LookBackViewModel?
    var onOpenLookBack: (LookBackItem) -> Void = { _ in }
    /// The partners' avatars at the top, with their stories. Nil hides the row.
    var stories: StoriesViewModel?
    var storyPeople: StoryPeople?
    /// The couple's letters. Nil hides the Mail card.
    var mail: MailViewModel?
    /// The couple's memories, for the card that asks for photos after a visit. Nil hides it.
    var memories: MemoriesViewModel?
    var onRefresh: () async -> Void = {}
    /// The access notice this person closed (`AccessNotice.id`). A new notice shows again.
    @AppStorage("home.accessNotice.dismissed") var dismissedAccessNoticeID = ""
    /// The next visit and the couple's list (`HomeVisitCard`). Nil hides the card.
    @Environment(VisitsViewModel.self) var visits: VisitsViewModel?
    @Environment(RecapViewModel.self) var recap: RecapViewModel?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// iPad landscape: three columns that the cards fill left to right and then down,
    /// with a square map (`HomeWideLayout`).
    @State var isWideLayout = false
    /// A sheet from one of the cards is up (`HomeIsCoveredKey`).
    @State var isCovered = false
    @State var visitMemoryForm: VisitMemoryForm?
    /// `mapTiles.showsMapHeader`, changed inside an animation so the layouts cross-fade.
    @State private var showsMapHeader: Bool
    /// Both layouts are on screen while one fades into the other.
    @State private var isSwitchingLayout = false
    @State private var layoutSwitchTask: Task<Void, Never>?
    /// Moves the cards both layouts share from one layout's place to the other's.
    @Namespace private var layoutSwitch

    private static let alertTypesSeenOnHome: Set<String> = [
        "widget_updated", "streak_reminder", "story_posted", "date_reminder", "partner_joined", "letter_arrived",
    ]

    init(
        currentUserID: UUID? = nil,
        coupleID: UUID? = nil,
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerDisplayName: String?,
        partnerProfilePhotoAssetID: UUID? = nil,
        accessNotice: AccessNotice? = nil,
        relationshipStartedOn: String? = nil,
        milestoneIsSaving: Bool = false,
        milestoneIsLoading: Bool = false,
        onSaveRelationshipStartedOn: @escaping (Date) async -> Bool = { _ in false },
        coupleDates: CoupleDatesViewModel? = nil,
        coupleDateNames: CoupleDateNames = CoupleDateNames(),
        dailyChallengeCardState: DailyChallengeCardState = DailyChallengeCardState(kind: .loading),
        dailyChallengeStreak: StreakPillState = .hidden,
        zoomNamespace: Namespace.ID? = nil,
        locationMapState: CoupleMapState,
        mapTiles: HomeMapTileStatus,
        onPromptCurrentLocation: @escaping () -> Void = {},
        onPauseLocationSharing: ((Date) -> Void)? = nil,
        unreadChats: [UnreadChatRow] = [],
        onOpenChat: @escaping (UUID) -> Void = { _ in },
        games: GamesViewModel? = nil,
        hearts: HeartsViewModel? = nil,
        onOpenGame: @escaping (GamesDestination) -> Void = { _ in },
        onTapStreak: (() -> Void)? = nil,
        onOpenDailyChallenge: @escaping () -> Void = {},
        onOpenPartnerQuestion: @escaping (UUID) -> Void = { _ in },
        firstSteps: HomeFirstSteps? = nil,
        onOpenFirstStep: @escaping (HomeFirstStep) -> Void = { _ in },
        onCloseFirstSteps: @escaping () -> Void = {},
        onOpenWidgetDrawing: @escaping () -> Void = {},
        lookBack: LookBackViewModel? = nil,
        onOpenLookBack: @escaping (LookBackItem) -> Void = { _ in },
        stories: StoriesViewModel? = nil,
        storyPeople: StoryPeople? = nil,
        mail: MailViewModel? = nil,
        memories: MemoriesViewModel? = nil,
        onRefresh: @escaping () async -> Void = {}
    ) {
        self.currentUserID = currentUserID
        self.coupleID = coupleID
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.accessNotice = accessNotice
        self.relationshipStartedOn = relationshipStartedOn
        self.milestoneIsSaving = milestoneIsSaving
        self.milestoneIsLoading = milestoneIsLoading
        self.onSaveRelationshipStartedOn = onSaveRelationshipStartedOn
        self.coupleDates = coupleDates
        self.coupleDateNames = coupleDateNames
        self.dailyChallengeCardState = dailyChallengeCardState
        self.dailyChallengeStreak = dailyChallengeStreak
        self.zoomNamespace = zoomNamespace
        self.locationMapState = locationMapState
        self.mapTiles = mapTiles
        _showsMapHeader = State(initialValue: mapTiles.showsMapHeader)
        self.onPromptCurrentLocation = onPromptCurrentLocation
        self.onPauseLocationSharing = onPauseLocationSharing
        self.unreadChats = unreadChats
        self.onOpenChat = onOpenChat
        self.games = games
        self.hearts = hearts
        self.onOpenGame = onOpenGame
        self.onTapStreak = onTapStreak
        self.onOpenDailyChallenge = onOpenDailyChallenge
        self.onOpenPartnerQuestion = onOpenPartnerQuestion
        self.firstSteps = firstSteps
        self.onOpenFirstStep = onOpenFirstStep
        self.onCloseFirstSteps = onCloseFirstSteps
        self.onOpenWidgetDrawing = onOpenWidgetDrawing
        self.lookBack = lookBack
        self.onOpenLookBack = onOpenLookBack
        self.stories = stories
        self.storyPeople = storyPeople
        self.mail = mail
        self.memories = memories
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollViewReader { proxy in
            homeContent
                .environment(\.homeScrollProxy, proxy)
                .modifier(VisitMemoryFormSheet(form: $visitMemoryForm, memories: memories, viewerID: currentUserID))
        }
        .onPreferenceChange(HomeIsCoveredKey.self) { covered in
            isCovered = covered
            if !covered, showsMapHeader != mapTiles.showsMapHeader {
                switchLayout(showingMapHeader: mapTiles.showsMapHeader)
            }
        }
        .paeoniaWideLayout($isWideLayout)
        .heartsLifecycle(hearts, ownerUserID: currentUserID, partnerName: partnerName)
        .lookBackRefresh(lookBack, userID: currentUserID, coupleID: coupleID)
        // Home shows the couple's current drawing, the streak, the story ring and the next
        // date, so seeing it means the user has noticed a new drawing, a check-in reminder,
        // a story or a date reminder.
        .task {
            await DeliveredNotifications.clear(types: Self.alertTypesSeenOnHome)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await DeliveredNotifications.clear(types: Self.alertTypesSeenOnHome)
                }
                Task { await mapTiles.checkOnReturn() }
            }
        }
        .task(id: mapTiles.tiles) {
            await mapTiles.watch()
        }
        .onChange(of: mapTiles.showsMapHeader) { _, shows in
            switchLayout(showingMapHeader: shows)
        }
        .onDisappear {
            layoutSwitchTask?.cancel()
            isSwitchingLayout = false
            showsMapHeader = mapTiles.showsMapHeader
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

}

extension PairedHomeView {
    /// Compact windows use the map as Home's header while OpenFreeMap can draw it. Otherwise
    /// they show the map card under the tiles, as a wide iPad does, with the same mark and
    /// streak at the top, so only the cards change.
    private var homeContent: some View {
        ZStack {
            if drawsOwnHeader && (showsMapHeader || isSwitchingLayout) {
                mapHeaderContent
                    .opacity(usesMapHeader ? 1 : 0)
                    .allowsHitTesting(usesMapHeader)
                    .accessibilityHidden(!usesMapHeader)
            }
            if !usesMapHeader || isSwitchingLayout {
                classicContent
                    .opacity(usesMapHeader ? 0 : 1)
                    .allowsHitTesting(!usesMapHeader)
                    .accessibilityHidden(usesMapHeader)
            }
        }
    }

    /// Puts the incoming layout on screen, hidden, then fades it in while the cards both
    /// layouts share move between their places. MapLibre holds up the main thread for a
    /// moment while it sets up a new map, and a fade that starts then jumps to its end, so
    /// the map header gets that moment before it fades in.
    private func switchLayout(showingMapHeader shows: Bool) {
        // Replacing a layout would dismiss its story or note editor. Wait until it closes.
        guard !isCovered else { return }
        layoutSwitchTask?.cancel()
        guard drawsOwnHeader, !reduceMotion else {
            isSwitchingLayout = false
            showsMapHeader = shows
            return
        }
        isSwitchingLayout = true
        layoutSwitchTask = Task {
            if shows {
                do {
                    try await Task.sleep(for: .milliseconds(600))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, mapTiles.showsMapHeader == shows else { return }
            guard !isCovered else {
                isSwitchingLayout = false
                return
            }
            withAnimation(PaeoniaMotion.homeLayoutChange) {
                showsMapHeader = shows
            } completion: {
                guard mapTiles.showsMapHeader == shows else { return }
                isSwitchingLayout = false
            }
        }
    }

    private var usesMapHeader: Bool {
        drawsOwnHeader && showsMapHeader
    }

    private var mapHeaderContent: some View {
        HomeMapLayout(
            mapState: locationMapState,
            partnerName: partnerName,
            stories: stories,
            storyPeople: storyPeople,
            hearts: hearts,
            mapTiles: mapTiles,
            onPromptCurrentLocation: onPromptCurrentLocation,
            onRefresh: onRefresh
        ) {
            markAndStreakRow
        } sheet: {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                notices
                partnerGameCard
                dailyPromptCard
                    .matchedGeometryEffect(
                        id: HomeLayoutSwitchCard.dailyPrompt, in: layoutSwitch, isSource: usesMapHeader
                    )
                unreadChatsCard
                anniversaryRecapCard
                waitingMailCard
                firstStepsCard
                visitCard
                waitingVisitMemoryCard
                milestoneAndWidget
                    .matchedGeometryEffect(id: HomeLayoutSwitchCard.tiles, in: layoutSwitch, isSource: usesMapHeader)
            }
            // On the map layout today's question sits on the page, with no card.
            .environment(\.dailyPromptIsInline, true)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space16)
        } footer: {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                visitMemoryAsk
                laterRecapCard
                writeMailRow
                lookBackCard
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space16)
        }
        // On the whole page, so the map and the avatars move with a card that changes height.
        .modifier(cardChangeAnimations)
    }

    private var classicContent: some View {
        ScrollView {
            classicCards
        }
        .scrollIndicators(.hidden)
        .refreshable { await onRefresh() }
    }

    private var classicCards: some View {
        // One layout for phone and wide iPad keeps the cards' identity, so turning
        // the iPad doesn't reset them or close the milestone sheet. The spacing
        // matches the gap inside the milestone/drawing tile row so the cards read
        // as one grid. The partner's game leads while they are in it, because it
        // is the one card that can't wait. Then today's questions, and the tiles
        // sit above the map, so a milestone day's celebration plays on screen.
        // The header with the partners' story avatars sits above every card, also on a wide iPad.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            homeHeader
            notices
            cardsLayout {
                partnerGameCard
                dailyPromptCard
                    .matchedGeometryEffect(
                        id: HomeLayoutSwitchCard.dailyPrompt, in: layoutSwitch, isSource: !usesMapHeader
                    )
                unreadChatsCard
                anniversaryRecapCard
                waitingMailCard
                firstStepsCard
                visitCard
                waitingVisitMemoryCard
                milestoneAndWidget
                    .matchedGeometryEffect(
                        id: HomeLayoutSwitchCard.tiles, in: layoutSwitch, isSource: !usesMapHeader
                    )
                    .layoutValue(key: HomeWideRole.self, value: .tiles)
                mapCard
                visitMemoryAsk
                laterRecapCard
                writeMailRow
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
        .modifier(cardChangeAnimations)
    }

    /// Both layouts glide their cards with the same changes.
    private var cardChangeAnimations: HomeCardChangeAnimations {
        HomeCardChangeAnimations(
            animation: reduceMotion ? nil : PaeoniaMotion.homeLayoutChange,
            hasUnreadChats: !unreadChats.isEmpty,
            accessNotice: accessNotice,
            isStreakSavable: dailyChallengeStreak.isSavable,
            partnerGame: games?.partnerGame?.kind,
            lookBack: lookBack?.item,
            firstSteps: firstSteps,
            dailyCard: dailyChallengeCardState.kind,
            milestoneIsLoading: milestoneIsLoading,
            relationshipStartedOn: relationshipStartedOn,
            visitCard: visits?.homeCard(at: Date(), streak: dailyChallengeStreak),
            waitingLetters: mail?.waiting.count ?? 0,
            visitMemoryCard: visitMemoryPrompts
        )
    }

    /// iPhone, which is portrait only, and a narrow iPad window, where the tab bar is at
    /// the bottom and the top row is free.
    var drawsOwnHeader: Bool {
        horizontalSizeClass != .regular
    }
}

private enum HomeLayoutSwitchCard {
    case dailyPrompt
    case tiles
}

/// The changes that add, remove or resize a Home card. The page animates on them as a
/// whole, so the cards under one that changes glide to their new place.
private struct HomeCardChangeAnimations: ViewModifier {
    let animation: Animation?
    let hasUnreadChats: Bool
    let accessNotice: AccessNotice?
    let isStreakSavable: Bool
    let partnerGame: GameKind?
    let lookBack: LookBackItem?
    let firstSteps: HomeFirstSteps?
    /// The daily card is tall until today's question is answered, then a short row.
    let dailyCard: DailyChallengeCardState.Kind
    let milestoneIsLoading: Bool
    let relationshipStartedOn: String?
    /// The visit card shows nothing until the cache is read, then a short question or a tall countdown.
    let visitCard: HomeVisitCardState?
    let waitingLetters: Int
    let visitMemoryCard: [VisitMemoryPrompt]

    func body(content: Content) -> some View {
        content
            .animation(animation, value: hasUnreadChats)
            .animation(animation, value: accessNotice)
            .animation(animation, value: isStreakSavable)
            .animation(animation, value: partnerGame)
            .animation(animation, value: lookBack)
            .animation(animation, value: firstSteps)
            .animation(animation, value: dailyCard)
            .animation(animation, value: milestoneIsLoading)
            .animation(animation, value: relationshipStartedOn)
            .animation(animation, value: visitCard)
            .animation(animation, value: waitingLetters)
            .animation(animation, value: visitMemoryCard)
    }
}

#Preview {
    NavigationStack {
        PairedHomeView(
            currentDisplayName: "Hjalmar",
            partnerDisplayName: "Oda",
            relationshipStartedOn: "2026-01-08",
            locationMapState: .partnerUnknown(.notSharing),
            mapTiles: HomeMapTileStatus()
        )
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
