import Foundation
import Observation

/// The whole Story Chain flow for one person. Screens bind to the observable
/// state and call the actions. They hold no game rules.
///
/// The state comes from three places that are combined on every change: the
/// server's state in the Story Chain cache (kept current by
/// `StoryChainLiveFeed`), the couple's settings and presence in the shared Games
/// cache, and the moves saved on this phone that have not been sent (the pending
/// operations). `StoryChainResolver` turns them into `phase`. Every move is
/// written to the pending operations first, so it works offline.
///
/// Files: this file holds the state, the reading and `recompute()`. The
/// extensions hold the lifecycle, the partner and the live room, the moves, and
/// the page.
@MainActor
@Observable
final class StoryChainViewModel {
    // MARK: - State the screens read
    //
    // Screens only read these. The view model and its extensions write them.

    private(set) var phase: StoryChainPhase = .loading
    /// The story the phase is about, with this phone's unsent moves applied. While
    /// an opening is chosen it is the story that just finished, if there is one.
    private(set) var story: StoryChainEffectiveStory?
    /// What the page draws: the story's lines, the partner's live draft, and the
    /// line that is writing itself in.
    private(set) var page = StoryChainPageContent(opening: nil, lines: [], ghost: nil, arrivingLineID: nil)

    // Choose an opening.
    private(set) var openingChoices: [RemoteStoryOpening] = []
    /// It is this person's turn to choose, the state has loaded, and it carries no
    /// openings. Only then does the screen show its offline message.
    private(set) var openingsUnavailable = false
    /// Why the last read of the server failed. Nil after a good read.
    private(set) var refreshFailure: PaeoniaFailure?
    var selectedOpening: StoryChainOpeningChoice?

    // Writing.
    var draft = "" {
        didSet {
            if draft != oldValue {
                if phase == .writing {
                    mayRestoreSavedDraft = false
                }
                sendDraftLive()
                saveDraftSoon()
            }
        }
    }
    /// The three words Paeonia suggests, while it is this person's turn to write.
    private(set) var wordChoices: [RemoteStoryDareWord] = []
    /// The word this person gives the partner with the line they are writing.
    var dareToGive: StoryChainDare?
    /// The "Make this the last line" switch. Read `isLastLine` for the effective value.
    var wantsLastLine = false

    // Naming.
    var titleDraft = ""
    /// The finished story the reveal shows. Set while `phase` is `.finished`.
    private(set) var finished: StoryChainFinishedStory?

    // Partner and live.
    private(set) var partnerPresence: StoryChainPartnerPresence = .away
    /// The partner's live draft is set to be the last line.
    private(set) var partnerIsWritingLast = false
    private(set) var invite: GameInviteState = .hidden

    // Sending.
    /// A move is saved on this phone and not sent yet. It may be on its way.
    private(set) var isWaitingToSend = false
    /// A waiting move has failed to send at least once, so it really is held on
    /// this phone. Show "saved on this phone".
    private(set) var isHeldOnPhone = false
    /// A waiting move could not be sent although the phone is online. The waiting
    /// screen says so and offers `retrySend()`.
    private(set) var isSendFailing = false
    /// Creating the game is in progress.
    var isStartingGame = false
    /// Why creating the game failed. The screen offers another try.
    var startFailure: PaeoniaFailure?
    var startFailed: Bool {
        startFailure != nil
    }
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: GamesNotice?

    private(set) var participants: GameParticipants

    // MARK: - Dependencies

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored var storyGateway: any StoryChainGateway { dependencies.storyChainGateway }
    @ObservationIgnored let moveQueue: StoryChainMoveQueue
    /// This person's private stars on finished stories. The finished screen and
    /// "Our stories" share it: `stars.isStarred(storyID)` and `stars.toggle(storyID:)`.
    @ObservationIgnored lazy var stars = StoryChainStars(dependencies: dependencies) { [weak self] in
        self?.currentUserID
    }
    @ObservationIgnored let heartbeatInterval: Duration
    @ObservationIgnored let tickInterval: Duration
    @ObservationIgnored let liveSendInterval: Duration
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?

    // MARK: - Internal state

    @ObservationIgnored var state: RemoteStoryChainState?
    @ObservationIgnored var settings: RemoteGameSettings?
    /// The shared overview's heartbeat and invite for this game.
    @ObservationIgnored var overviewPresence: RemoteGamePresence?
    @ObservationIgnored var pending = StoryChainPendingWork.none
    @ObservationIgnored var now: Date
    @ObservationIgnored var localInviteSentAt: Date?
    @ObservationIgnored var reloadGate = GameReloadGate()
    @ObservationIgnored var isRunning = false
    @ObservationIgnored var isActive = true
    @ObservationIgnored var hasEnsuredGame = false
    /// A start, line, or name is being saved. A second tap waits for it.
    @ObservationIgnored var isSavingMove = false

    /// The finished story the person named on this phone and still looks at.
    @ObservationIgnored var revealedStoryID: UUID?
    @ObservationIgnored var isNamingInFlight = false
    @ObservationIgnored var localFinishedDates: [UUID: Date] = [:]
    /// The line and story the composer was last reset for.
    @ObservationIgnored var writingKey: StoryChainWritingKey?
    @ObservationIgnored var namingStoryID: UUID?
    /// The composer's text as the Story Chain cache keeps it, and what this view
    /// model last wrote there. A saved draft that differs is from before a
    /// relaunch, so it goes back into an empty composer.
    @ObservationIgnored var savedDraft: String?
    @ObservationIgnored var lastDraftWritten: String?
    @ObservationIgnored var draftSaveTask: Task<Void, Never>?
    /// The cache holds words of refused lines for the next composer.
    @ObservationIgnored var hasRescuedLines = false
    @ObservationIgnored var isTakingRescuedLines = false
    /// The saved draft may go back into the composer once per opening of the
    /// screen, before the person edits anything. A later read could be older
    /// than an edit, such as text the person just deleted.
    @ObservationIgnored var mayRestoreSavedDraft = true

    /// Lines that wrote themselves in during this app session, so none repeats.
    @ObservationIgnored var animatedLineIDs: Set<UUID> = []
    @ObservationIgnored var arrivingLineID: UUID?
    @ObservationIgnored var arrivalPace = StoryChainArrivalTiming.partner

    // The live room.
    @ObservationIgnored var live: WidgetLiveDrawing?
    @ObservationIgnored var liveChannel: GameLiveChannel<StoryChainLiveMessage>?
    @ObservationIgnored var partnerMessage: StoryChainReceivedMessage?
    @ObservationIgnored var liveWindowTask: Task<Void, Never>?
    @ObservationIgnored var liveDraftIsDirty = false
    /// The line this person sent live, so no later draft message follows it.
    @ObservationIgnored var liveSentKey: StoryChainWritingKey?

    @ObservationIgnored var observationTask: Task<Void, Never>?
    @ObservationIgnored var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored var tickTask: Task<Void, Never>?
    @ObservationIgnored var liveObservationTask: Task<Void, Never>?
    @ObservationIgnored var startTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?

    init(
        dependencies: GamesDependencies,
        participants: GameParticipants = GameParticipants(),
        heartbeatInterval: Duration = GamePresence.heartbeatInterval,
        tickInterval: Duration = .seconds(1),
        liveSendInterval: Duration = .milliseconds(50),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.dependencies = dependencies
        self.participants = participants
        self.heartbeatInterval = heartbeatInterval
        self.tickInterval = tickInterval
        self.liveSendInterval = liveSendInterval
        self.sleep = sleep
        moveQueue = StoryChainMoveQueue(dependencies: dependencies)
        now = dependencies.now()
        if let coupleID = participants.coupleID, let room = dependencies.makeStoryChainLive(coupleID) {
            attach(room)
        }
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        participants.partnerName
    }

    /// Names who is playing. Safe to call again when the names load. A change of
    /// user or couple resets what was loaded.
    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        if identityChanged {
            resetForNewIdentity()
        }
        if live == nil, let coupleID = newParticipants.coupleID, let room = dependencies.makeStoryChainLive(coupleID) {
            attach(room)
        }
        if isRunning {
            Task { await reload() }
        }
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        syncAfterLocalChange = handler
        stars.setLocalChangeSyncHandler(handler)
    }

    func clearNotice() {
        notice = nil
    }

    // MARK: - Reading

    /// Re-reads the caches and the queue, then works out the phase.
    func reload() async {
        guard let userID = currentUserID else { return }
        let reloadTicket = reloadGate.begin()
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        let document = await dependencies.storyChainCache.document(ownerUserID: userID)
        let work = await StoryChainPendingWork.load(from: dependencies.pendingOperationStore, ownerUserID: userID)
        // Taken before the check below: a notice is gone from the cache once taken.
        let notices = await dependencies.storyChainCache.takeNotices(ownerUserID: userID)
        if currentUserID == userID, let first = notices.first {
            notice = GamesNotice(first)
        }
        guard currentUserID == userID, reloadGate.apply(reloadTicket) else { return }

        state = document.state
        savedDraft = document.draft
        hasRescuedLines = !document.rescuedLines.isEmpty
        settings = overview?.settings
        overviewPresence = overview?.presence(for: .storyChain)
        // A queue that could not be read keeps what the screen shows.
        if let work {
            pending = work
        }
        recompute()
    }

    /// Reads the server's state once and caches it.
    func refresh() async {
        guard let userID = currentUserID else { return }
        do {
            guard try await dependencies.storyChainCache.fetchState(from: storyGateway, ownerUserID: userID),
                  !Task.isCancelled
            else { return }
            refreshFailure = nil
        } catch {
            if !Task.isCancelled {
                refreshFailure = PaeoniaFailure(error)
            }
            return
        }
        await reload()
    }

    // MARK: - Working out the screen

    /// Combines the server's state and the unsent moves into the observable
    /// state, then runs the effects a new state needs.
    func recompute() {
        guard let userID = currentUserID else { return }
        now = dependencies.now()
        let resolution = StoryChainResolver(userID: userID).resolve(state: state, settings: settings, pending: pending)
        phase = resolvedPhase(for: resolution)
        story = resolution.story
        isWaitingToSend = resolution.isWaitingToSend
        isHeldOnPhone = isWaitingToSend && pending.isHeldOnPhone
        isSendFailing = isWaitingToSend && pending.lastSendFailedWhileOnline
        if phase != .preparing {
            startFailure = nil
        }

        resetComposerForNewTurn()
        restoreDraftIfNeeded()
        openingChoices = phase == .chooseOpening ? state?.openingChoices ?? [] : []
        openingsUnavailable = phase == .chooseOpening && openingChoices.isEmpty
        wordChoices = phase == .writing ? state?.wordChoices ?? [] : []
        dropStaleChoices()
        finished = makeFinished()
        partnerPresence = currentPartnerPresence()
        partnerIsWritingLast = freshPartnerDraft?.isLast == true
        invite = GameInviteState.make(
            lastInviteAt: overviewPresence?.lastInviteAt,
            localSentAt: localInviteSentAt,
            partnerIsHere: partnerPresence.isHere,
            now: now
        )
        startArrivalIfNeeded()
        page = makePage()

        live?.switchRole(to: StoryChainResolver.liveRole(for: phase))
        startGameIfNeeded()
    }

    /// Shows nothing until the next read, such as after another person signs in.
    func clearDisplayedState() {
        phase = .loading
        story = nil
        page = StoryChainPageContent(opening: nil, lines: [], ghost: nil, arrivingLineID: nil)
        finished = nil
    }

    /// The phase the screen shows. The partner who just named a story keeps
    /// seeing its reveal until they continue, although the resolver already
    /// moved on to choosing an opening.
    private func resolvedPhase(for resolution: StoryChainResolution) -> StoryChainPhase {
        guard let revealedID = revealedStoryID else { return resolution.phase }
        if resolution.story?.id == revealedID, resolution.story?.story.state == .finished {
            return .finished(storyID: revealedID)
        }
        // The name was refused, or the story is gone. Back to the resolver's phase.
        if !isNamingInFlight {
            revealedStoryID = nil
        }
        return resolution.phase
    }

    /// A choice that is no longer on offer, such as after a language change.
    private func dropStaleChoices() {
        if phase != .chooseOpening {
            selectedOpening = nil
        } else if case let .opening(opening) = selectedOpening, !openingChoices.contains(opening) {
            selectedOpening = nil
        }
        // A suggested word the server no longer offers, such as after a language change.
        if let wordID = dareToGive?.wordID, !wordChoices.isEmpty,
           !wordChoices.contains(where: { $0.wordID == wordID }) {
            dareToGive = nil
        }
    }
}
