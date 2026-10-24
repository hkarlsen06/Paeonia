import SwiftUI

/// Who is signed in and who they are paired with, as the tabs need it.
struct MainTabIdentity: Equatable {
    var currentUserID: UUID?
    var currentDisplayName: String?
    var currentProfilePhotoAssetID: UUID?
    var currentCustomProfilePhotoAssetID: UUID?
    var currentProviderProfilePhotoAssetID: UUID?
    var partnerUserID: UUID?
    /// What this person calls their partner. Show `partnerDisplayName`, never the partner's own name.
    var partnerName: PartnerName?
    var partnerProfilePhotoAssetID: UUID?
    /// The active couple, needed to create new memories. Cosmetic for the rest of the
    /// tabs, so it must not be part of any load-bearing `.task(id:)` key.
    var coupleID: UUID?
    /// The day the relationship started (`yyyy-MM-dd`), used by the Home tab milestone
    /// countdown. Display-only, so it never keys a load.
    var relationshipStartedOn: String?
    /// What this person has without their partner's subscription. The leave
    /// confirmation says what happens to it.
    var ownAccess: OwnAccess = .nothing
    /// The notice Home shows before access ends. Display-only.
    var accessNotice: AccessNotice?

    /// The partner's name as this person sees it: their nickname, otherwise the partner's own name.
    var partnerDisplayName: String? {
        partnerName?.display
    }
}

/// Keys the tab bar's loads that wait for the cold-launch intro. Like the plain
/// user key, it leaves out names and photos, so those arriving never restart a load.
private struct IntroGatedLoadKey: Hashable {
    var userID: UUID?
    var introComplete: Bool
}

/// Root-owned work the tabs ask for.
struct MainTabActions {
    var openWidgetDrawing: () -> Void = {}
    /// The map card's Share button. Turns sharing on and offers sharing while closed.
    var shareLocation: @MainActor () async -> Void = {}
    /// The person answered a question or sent a drawing.
    var sentSomethingToPartner: (PartnerShare) -> Void = { _ in }
    /// Pull-to-refresh on Home, after the daily challenge refresh.
    var refreshHome: () async -> Void = {}
    /// Runs one sync pass so a daily challenge refresh sees partner answers.
    var refreshDailyChallenge: () async -> Void = {}
    /// Sends local changes (answers, memories, start date) now.
    var syncAfterLocalChange: @MainActor @Sendable () async -> Void = {}
    /// The user unpaired, so the root resolves access again.
    var leftRelationship: () -> Void = {}
    var logOut: () -> Void = {}
    /// True while a log-out runs, so the log-out row shows progress.
    var isLoggingOut = false
    /// Runs after the paired Settings confirmation. Auth/session lifecycle
    /// stays rooted rather than being duplicated in the Settings view model.
    var deleteAccount: () -> Void = {}
    /// Saves the paired user's canonical profile through the root-owned auth
    /// service so every tab receives the resulting session in one update.
    var updateProfile: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool = { _, _ in false }
    /// Re-resolves entitlement/access after StoreKit has re-confirmed a purchase.
    var purchasesRestored: @MainActor @Sendable () async -> Void = {}
}

/// The tabs' long-lived view models. `MainTabView` keeps one in `@State`, and
/// the models are built on first use. A SwiftUI view initializer runs on every
/// parent update, so building them there would make and throw away four view
/// models each time.
@MainActor
final class MainTabModels {
    private let dependencies: RootFeatureDependencies

    init(dependencies: RootFeatureDependencies) {
        self.dependencies = dependencies
    }

    lazy var dailyChallenge: DailyChallengeViewModel =
        dependencies.dailyChallengeViewModel ?? DailyChallengeViewModel()
    lazy var milestone: RelationshipMilestoneViewModel =
        dependencies.milestoneViewModel ?? RelationshipMilestoneViewModel()
    lazy var memories: MemoriesViewModel =
        dependencies.memoriesViewModel ?? MemoriesViewModel()
    lazy var games: GamesViewModel =
        dependencies.gamesViewModel ?? GamesViewModel(dependencies: .live())
    lazy var hearts = HeartsViewModel()
    lazy var coupleDates = CoupleDatesViewModel()
    lazy var stories = StoriesViewModel()
    lazy var search = SearchViewModel.live()
    /// The memories' comments and the stories' replies the partner wrote in and the user has not read.
    lazy var chatSummaries = ThreadChatSummaries(service: dailyChallenge.chatService)
    lazy var reactions = ReactionStore()
    lazy var topics = TopicsViewModel()
    lazy var lookBack = LookBackViewModel.live(
        thumbnailLoader: dependencies.widgetHistoryThumbnailLoader
            ?? WidgetRevisionThumbnailLoader(gateway: WidgetDrawingHistoryFactory.makeGateway())
    )
    private var settingsModel: SettingsViewModel?

    /// Built for the first signed-in user it is asked for, like the
    /// `SettingsView` state that held it before.
    func settings(userID: UUID?) -> SettingsViewModel {
        if let settingsModel {
            return settingsModel
        }
        let model = dependencies.settingsViewModel ?? SettingsViewModel(userID: userID?.uuidString)
        settingsModel = model
        return model
    }
}

/// The native tab bar shown once a couple is paired.
///
/// Tab selection is owned by `RootViewModel` and passed in as a binding. That lets
/// navigation intent, such as opening the widget drawing screen from the Home
/// Screen widget, select the Home tab and present its destination in one atomic
/// update, so the screen can never open hidden behind another tab. Deep links,
/// the daily answer flows, and the streak sheets live in `MainTabView+Flows.swift`.
struct MainTabView: View {
    let tabs: [MainTab]
    let identity: MainTabIdentity
    let locationMapState: CoupleMapState
    let locationViewModel: LocationMapViewModel
    let selection: Binding<MainTab>
    let widgetDrawingPresented: Binding<Bool>
    let deepLink: Binding<PaeoniaDeepLink?>
    let actions: MainTabActions
    let dependencies: RootFeatureDependencies

    @State var models: MainTabModels
    @State var isAnswerFlowPresented = false
    /// Which card the daily answer flow should zoom out of (the Home prompt card or the
    /// Questions-tab hero card), so the cover grows from the one the user tapped.
    @State var dailyFlowSource: DailyFlowSource = .home
    /// Set when Home's "See your answers" opens the flow while the partner has
    /// answers today, so closing it lands on the Questions tab to read them.
    @State var returnsToQuestionsOnClose = false
    /// Streak-restore offer opened from the streak badge when a lost streak can still
    /// be bought back, outside the answer flow.
    @State var showStreakRestore = false
    /// Read-only streak detail sheet, opened by tapping the streak badge while the
    /// streak is healthy (nothing to restore).
    @State var showStreakDetail = false
    /// The Search sheet, opened from the search button in a tab's navigation bar.
    @State var isSearchPresented = false
    /// The streak milestone moment, shown once per milestone on this phone, or again
    /// from the streak badge for the rest of that streak day.
    @State var streakMilestone: StreakMilestoneMoment?
    /// The Questions-tab single-question partner-answer flow. The tapped question drives
    /// presentation and is the card the cover zooms out of.
    @State var partnerAnswerQuestion: DailyChallengeQuestion?
    /// The partner-answer flow was opened from a locked row on the Home card, so it
    /// zooms out of that row and not out of the Questions tab list.
    @State var partnerAnswerOpenedFromHome = false
    /// Questions to scroll to and briefly highlight, after a notification deep link
    /// or a button that sends the user to answer the partner's questions.
    @State var focusedDailyQuestionIDs: [UUID] = []
    @State var dailyChatQuestion: DailyChallengeQuestion?
    /// What the Questions tab has pushed: the Topics shelf and a topic.
    @State var questionsPath: [QuestionsDestination] = []
    /// The Memories tab's stack, so the Home look-back card can open a memory in it.
    @State var memoriesPath: [UUID] = []
    /// The drawing history, opened from the Home look-back card.
    @State var isLookBackDrawingHistoryPresented = false
    /// What the Games tab has open. A notification about a game sets it.
    @State var gamesPath: [GamesDestination] = []
    /// The time the Home tab badge counts unseen stories at. It moves forward when the
    /// stories change and when an unseen story leaves Home.
    @State var storyBadgeDate = Date()
    /// The signed-in user's photo, cropped to a circle for the You tab icon.
    @Namespace var zoomNamespace
    @Environment(PaeoniaBannerCenter.self) var bannerCenter
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) var scenePhase
    /// False while the cold-launch intro still covers the app. The streak milestone
    /// moment waits for it.
    @Environment(\.launchIntroComplete) var launchIntroComplete

    init(
        tabs: [MainTab] = MainTab.allCases,
        identity: MainTabIdentity,
        locationMapState: CoupleMapState,
        locationViewModel: LocationMapViewModel,
        selection: Binding<MainTab>,
        widgetDrawingPresented: Binding<Bool>,
        deepLink: Binding<PaeoniaDeepLink?> = .constant(nil),
        actions: MainTabActions = MainTabActions(),
        dependencies: RootFeatureDependencies? = nil
    ) {
        let dependencies = dependencies ?? RootFeatureDependencies()
        self.tabs = tabs
        self.identity = identity
        self.locationMapState = locationMapState
        self.locationViewModel = locationViewModel
        self.selection = selection
        self.widgetDrawingPresented = widgetDrawingPresented
        self.deepLink = deepLink
        self.actions = actions
        self.dependencies = dependencies
        _models = State(initialValue: MainTabModels(dependencies: dependencies))
    }

    var dailyChallengeViewModel: DailyChallengeViewModel { models.dailyChallenge }
    var milestoneViewModel: RelationshipMilestoneViewModel { models.milestone }
    var memoriesViewModel: MemoriesViewModel { models.memories }
    var gamesViewModel: GamesViewModel { models.games }
    var lookBackViewModel: LookBackViewModel { models.lookBack }
    var heartsViewModel: HeartsViewModel { models.hearts }
    var coupleDatesViewModel: CoupleDatesViewModel { models.coupleDates }
    /// The stars on questions, answers, drawings and finished games. One store for the whole app.
    var favoritesStore: FavoritesStore { .shared }
    var storiesViewModel: StoriesViewModel { models.stories }
    var chatSummaries: ThreadChatSummaries { models.chatSummaries }
    var reactionStore: ReactionStore { models.reactions }
    var topicsViewModel: TopicsViewModel { models.topics }

    var body: some View {
        presentingSearch(on: presentingDailyFlows(on: tabContent))
            // Outside the covers and sheets, so the Home drawing, the story viewer and every game
            // screen can show and take reactions.
            .environment(reactionStore)
            // Memory comments and story replies open as chats from their own screens.
            .environment(\.threadChatContext, threadChatContext)
            .task(id: introGatedLoadKey) {
                guard introGatedLoadKey.introComplete else { return }
                await chatSummaries.observe(ownerUserID: identity.currentUserID)
            }
            .liveFeedDemand(visibleTab: selection.wrappedValue, partnerGames: gamesViewModel.partnerGameKinds)
    }

    private var tabContent: some View {
        TabView(selection: selection) {
            ForEach(tabs) { tab in
                content(for: tab)
                    .tag(tab)
                    .badge(badgeCount(for: tab))
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                            .accessibilityIdentifier("mainTab.\(tab.rawValue)")
                    }
            }
        }
        .tint(.paeoniaAccentPrimary)
        // Key the load on the signed-in user alone. The partner id, display names,
        // and profile photos all populate/refresh shortly after launch; if they were
        // in this id, every one of those changes would cancel and restart the task,
        // killing an in-flight question fetch with URLError.cancelled. Cosmetic
        // identity instead flows through refreshParticipants below, which never
        // reloads. See the `.task(id:)` note in AGENTS.md.
        .task(id: identity.currentUserID) {
            dailyChallengeViewModel.setLocalChangeSyncHandler(actions.syncAfterLocalChange)
            await dailyChallengeViewModel.configure(participants: dailyChallengeParticipants)
        }
        .onChange(of: dailyChallengeParticipants) { _, participants in
            dailyChallengeViewModel.refreshParticipants(participants)
        }
        // Topics answer through the daily challenge, so it is attached first. Only
        // the Questions tab shows them, so they wait for the intro.
        .task(id: introGatedLoadKey) {
            guard introGatedLoadKey.introComplete else { return }
            topicsViewModel.attach(dailyChallenge: dailyChallengeViewModel)
            await topicsViewModel.configure(currentUserID: identity.currentUserID, coupleID: identity.coupleID)
        }
        .onChange(of: identity.coupleID) { _, coupleID in
            // Before the intro ends, the deferred load above reads the couple itself.
            guard launchIntroComplete else { return }
            Task { await topicsViewModel.configure(currentUserID: identity.currentUserID, coupleID: coupleID) }
        }
        // A partner message in a topic question's chat brings the question back to
        // the Questions tab's list, so its topic is followed.
        .onChange(of: dailyChallengeViewModel.unreadChats.compactMap(\.topicKey)) {
            topicsViewModel.followWaitingTopics()
        }
        // The Games tab's badge needs the game state before the tab is opened, so
        // the tab bar loads and follows it once the intro has ended.
        .task(id: introGatedLoadKey) {
            guard introGatedLoadKey.introComplete else { return }
            gamesViewModel.configure(participants: gamesParticipants)
            await gamesViewModel.load()
        }
        .task(id: introGatedLoadKey) {
            guard introGatedLoadKey.introComplete else { return }
            await gamesViewModel.observeStoreChanges()
        }
        .onChange(of: gamesViewModel.partnerGameKinds) { old, new in
            announcePartnerGame(GamesViewModel.openedPartnerGame(from: old, to: new))
        }
        // Names, photos and the couple arrive after launch. They never reload the games.
        .onChange(of: gamesParticipants) { _, participants in gamesViewModel.configure(participants: participants) }
        .task(id: identity.currentUserID) {
            // A closure literal, because the stored value read out of the non-Sendable
            // MainTabActions counts as non-Sendable here.
            gamesViewModel.setLocalChangeSyncHandler { await actions.syncAfterLocalChange() }
        }
        .task(id: identity.currentUserID) {
            heartsViewModel.setSyncAfterLocalChange { await actions.syncAfterLocalChange() }
        }
        .task(id: identity.currentUserID) {
            milestoneViewModel.setSyncAfterLocalChange(actions.syncAfterLocalChange)
            await milestoneViewModel.configure(
                ownerUserID: identity.currentUserID,
                serverStartedOn: identity.relationshipStartedOn
            )
        }
        .task(id: identity.currentUserID) {
            coupleDatesViewModel.setSyncAfterLocalChange { await actions.syncAfterLocalChange() }
            await coupleDatesViewModel.configure(ownerUserID: identity.currentUserID)
            await coupleDatesViewModel.observeStoreChanges()
        }
        .onChange(of: coupleDatesViewModel.error) { _, error in
            guard let error else { return }
            bannerCenter.show(.error(message: error.message))
            coupleDatesViewModel.clearError()
        }
        .task(id: introGatedLoadKey) {
            guard introGatedLoadKey.introComplete else { return }
            favoritesStore.setLocalChangeSyncHandler { await actions.syncAfterLocalChange() }
            await favoritesStore.configure(ownerUserID: identity.currentUserID)
            await favoritesStore.observeStoreChanges()
        }
        .onChange(of: favoritesStore.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            favoritesStore.clearNotice()
        }
        .task(id: identity.currentUserID) {
            await storiesViewModel.configure(ownerUserID: identity.currentUserID, coupleID: identity.coupleID)
            await storiesViewModel.observeStoreChanges()
        }
        .onChange(of: identity.coupleID) { _, coupleID in
            storiesViewModel.updateCoupleID(coupleID)
        }
        .task(id: introGatedLoadKey) {
            guard introGatedLoadKey.introComplete else { return }
            await reactionStore.configure(ownerUserID: identity.currentUserID, partnerName: reactionPartnerName)
            await reactionStore.observeStoreChanges()
        }
        .onChange(of: reactionPartnerName) { _, name in
            reactionStore.updatePartnerName(name)
        }
        .task(id: StoryBadgeKey(stories: storiesViewModel.stories, partner: identity.partnerUserID)) {
            await refreshStoryBadge()
        }
        .onChange(of: storiesViewModel.error) { _, error in
            guard let error else { return }
            bannerCenter.show(.error(message: error.message))
            storiesViewModel.clearError()
        }
        .onChange(of: identity.relationshipStartedOn) { _, startedOn in
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
    }

    /// The loads that only the other tabs and small badges need start once the cold
    /// launch intro has ended, so Home's first build has the main thread to itself.
    private var introGatedLoadKey: IntroGatedLoadKey {
        IntroGatedLoadKey(userID: identity.currentUserID, introComplete: launchIntroComplete)
    }

    /// The partner's name in the words that say who reacted.
    var reactionPartnerName: String {
        identity.partnerDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationPartnerName)
    }

    /// What a memory's comments and a story's replies need to open as a chat.
    var threadChatContext: ThreadChatContext {
        ThreadChatContext(
            coupleID: identity.coupleID,
            participants: dailyChallengeParticipants,
            summaries: chatSummaries,
            service: dailyChallengeViewModel.chatService,
            operationProvider: dailyChallengeViewModel.operationProvider,
            syncAfterLocalChange: actions.syncAfterLocalChange,
            reporting: ChatReporting(
                service: dependencies.settingsPrivacyService,
                operationProvider: dependencies.settingsPrivacyOperationProvider,
                onReportedAndLeft: actions.leftRelationship
            )
        )
    }

    /// Both partners' identity, used by the daily challenge to label partner-choice
    /// answers. A change of signed-in user reloads; a partner name change just
    /// relabels.
    var dailyChallengeParticipants: DailyChallengeParticipants {
        DailyChallengeParticipants(
            currentUserID: identity.currentUserID,
            currentDisplayName: identity.currentDisplayName,
            currentProfilePhotoAssetID: identity.currentProfilePhotoAssetID,
            partnerUserID: identity.partnerUserID,
            partnerDisplayName: identity.partnerDisplayName,
            partnerProfilePhotoAssetID: identity.partnerProfilePhotoAssetID
        )
    }
}

#if DEBUG
#Preview {
    MainTabView(
        identity: MainTabIdentity(
            currentUserID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            currentDisplayName: "Hjalmar",
            partnerUserID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
            partnerName: PartnerName(accountName: "Oda", nickname: nil),
            coupleID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
            relationshipStartedOn: "2026-01-08"
        ),
        locationMapState: .partnerUnknown(.notSharing),
        locationViewModel: LocationMapViewModel(),
        selection: .constant(.home),
        widgetDrawingPresented: .constant(false)
    )
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
