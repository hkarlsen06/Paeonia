import Observation
import PencilKit
import QuartzCore
import SwiftUI

/// Who is playing, as the game needs it.
nonisolated struct DrawAndGuessParticipants: Equatable, Sendable {
    var currentUserID: UUID?
    var coupleID: UUID?
    var partnerName: String
    /// The signed-in person's name and photo, for the avatars. They never reset the game.
    var currentName: String
    var currentPhotoAssetID: UUID?
    var partnerPhotoAssetID: UUID?

    init(
        currentUserID: UUID? = nil,
        coupleID: UUID? = nil,
        partnerName: String = "",
        currentName: String = "",
        currentPhotoAssetID: UUID? = nil,
        partnerPhotoAssetID: UUID? = nil
    ) {
        self.currentUserID = currentUserID
        self.coupleID = coupleID
        self.partnerName = partnerName
        self.currentName = currentName
        self.currentPhotoAssetID = currentPhotoAssetID
        self.partnerPhotoAssetID = partnerPhotoAssetID
    }
}

extension DrawAndGuessParticipants {
    /// Both people as the avatars show them.
    var players: (me: DrawAndGuessPlayer, partner: DrawAndGuessPlayer) {
        (
            DrawAndGuessPlayer(name: currentName, photoAssetID: currentPhotoAssetID),
            DrawAndGuessPlayer(name: partnerName, photoAssetID: partnerPhotoAssetID)
        )
    }
}

/// A person as the avatars show them.
nonisolated struct DrawAndGuessPlayer: Equatable, Sendable {
    var name: String
    var photoAssetID: UUID?
}

/// The whole Draw & Guess flow for one person. Screens bind to the observable
/// state and call the actions. They hold no game rules.
///
/// The state comes from three places that are combined on every change:
/// the server's state in the Games cache (kept current by `DrawAndGuessLiveFeed`),
/// the moves saved on this phone that have not been sent (the pending operations),
/// and the results this person has moved past (marked on the server, or waiting
/// in the pending operations). `DrawAndGuessResolver` turns them into `phase`.
/// Every move is written to the pending operations first, so it works offline.
///
/// Files: this file holds the state and the lifecycle. The turn actions, the
/// guess handling, the reveal, and the partner/live parts are in the extensions.
@MainActor
@Observable
final class DrawAndGuessViewModel {
    // MARK: - State the screens read
    //
    // Screens only read these. The view model and its extensions write them.

    var phase: DrawAndGuessPhase = .loading
    /// The round the phase is about, with this phone's unsent moves applied.
    var round: DrawAndGuessRoundView?
    var settings: RemoteGameSettings?
    var score: DrawAndGuessScore?
    var partnerName: String
    var me: DrawAndGuessPlayer
    var partner: DrawAndGuessPlayer
    /// The three words, while it is this person's turn to pick one.
    var choices: [DrawAndGuessWordChoice] = []
    /// It is this person's turn to pick, the state has loaded, and it carries no
    /// words. Only then does the choose screen show its offline message. Not
    /// having words while the round starts or the screen leaves is no failure.
    var choicesUnavailable = false
    /// The "Draw your own" text field. Bind to it.
    var customWord = "" {
        didSet { customWordValidation = DrawAndGuessCustomWordValidation(customWord) }
    }
    var customWordValidation: DrawAndGuessCustomWordValidation = .empty
    var tiles: [DrawAndGuessTile] = []
    var slots = DrawAndGuessSlots(answer: "") {
        didSet { sendGuessScreen() }
    }
    /// Goes up with each wrong full guess. Use it to trigger the shake and the haptic.
    var wrongGuessCount = 0
    /// Goes up when this person solves a round. Use it to trigger the success haptic.
    var solvedCount = 0
    /// The wrong guess stays in the slots for a moment before the tiles go back.
    var isShowingWrongGuess = false {
        didSet { sendGuessScreen() }
    }
    /// The screen sets this from Reduce Motion. The wrong word then stays a little
    /// longer and the tiles go back together.
    var prefersReducedMotion = false
    var partnerPresence: DrawAndGuessPartnerPresence = .away
    var invite: GameInviteState = .hidden
    /// The result screen is open and the partner has started the next round.
    /// The bottom button then reads "Watch [Name] draw" or "See what [Name] drew".
    var partnerNextRound: DrawAndGuessPartnerNextRound?
    /// Drawer only: the partner's guess screen while they are on it, from the live room.
    var partnerGuess: DrawAndGuessPartnerGuess?
    /// A move is saved on this phone and not sent yet. It may be on its way.
    var isWaitingToSend = false
    /// A waiting move has failed to send at least once, so it really is held on
    /// this phone. Show `.gamesPendingSavedOnPhone`.
    var isHeldOnPhone = false
    /// A move that waits could not be sent although the phone is online. The
    /// waiting screen then says so and offers `retrySending()`.
    var isSendFailing = false
    var reveal: DrawAndGuessReveal?
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: GamesNotice?
    var guessSource: DrawAndGuessGuessSource = .replay
    /// The partner's drawing is being fetched.
    var isLoadingDrawing = false
    /// The last fetch of the partner's drawing failed. `retryLoadingDrawing()` tries again.
    var drawingLoadFailed = false
    /// The drawing is playing, or ready to play, for the guesser.
    var isReplayReady = false
    var isFastForwarding = false
    /// Goes up whenever a drawing file finishes loading, so views that read
    /// `finalDrawing` update.
    var loadedDrawingVersion = 0
    /// The bonus for a fast guess. Always `.hidden` unless the couple plays against each other.
    var speedBonus: DrawAndGuessSpeedBonus = .hidden
    /// Creating the game, or sending a setting, is in progress.
    var isStartingGame = false
    var startFailed = false

    /// The drawer's canvas.
    let board = DrawAndGuessDrawingBoard()
    /// The relay room, nil when the couple has none.
    var live: WidgetLiveDrawing?
    /// The game's own messages in the relay room.
    @ObservationIgnored var liveGuessChannel: GameLiveChannel<DrawAndGuessLiveMessage>?
    @ObservationIgnored var lastSentGuessScreen: DrawAndGuessSentGuessScreen?
    @ObservationIgnored var receivedGuessScreen: DrawAndGuessReceivedGuessScreen?
    @ObservationIgnored var partnerReplayTimelineCache: (roundID: UUID, timeline: DrawAndGuessReplayTimeline)?

    // MARK: - Dependencies

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored var gateway: any GamesGateway { dependencies.gateway }
    /// This person's private stars on finished rounds. The result screens and
    /// "Our drawings" share it: `stars.isStarred(roundID)` and `stars.toggle(roundID:)`.
    @ObservationIgnored lazy var stars = DrawAndGuessStars(dependencies: dependencies) { [weak self] in
        self?.currentUserID
    }
    @ObservationIgnored let heartbeatInterval: Duration
    @ObservationIgnored let tickInterval: Duration
    @ObservationIgnored let monotonicNow: @Sendable () -> TimeInterval
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    /// The square's side from the drawing screen, for the result screen that follows it.
    @ObservationIgnored let squareMemory = DrawAndGuessSideMemory()
    @ObservationIgnored var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?

    // MARK: - Internal state

    @ObservationIgnored var participants: DrawAndGuessParticipants
    @ObservationIgnored var state: RemoteDrawAndGuessState?
    @ObservationIgnored var pending = DrawAndGuessPendingWork.none
    /// The answer slots the hints showed, by round. Kept in the Games cache too,
    /// so they survive leaving the screen and relaunching.
    @ObservationIgnored var persistedHints: [UUID: [Int]] = [:]
    @ObservationIgnored var now: Date
    @ObservationIgnored var localInviteSentAt: Date?
    @ObservationIgnored var isRunning = false
    /// The screen was open and went away. A stopped view model starts no
    /// downloads, replays or server calls until it starts again.
    @ObservationIgnored var isStopped = false
    @ObservationIgnored var isActive = true
    @ObservationIgnored var reloadGeneration = 0

    @ObservationIgnored var observationTask: Task<Void, Never>?
    @ObservationIgnored var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored var tickTask: Task<Void, Never>?
    @ObservationIgnored var liveObservationTask: Task<Void, Never>?
    @ObservationIgnored var wrongGuessTask: Task<Void, Never>?
    @ObservationIgnored var draftTask: Task<Void, Never>?
    @ObservationIgnored var startTask: Task<Void, Never>?
    @ObservationIgnored var drawingLoadTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?

    // Per round bookkeeping.
    @ObservationIgnored var tilesRoundID: UUID?
    @ObservationIgnored var tilesLanguage: GameLanguage?
    @ObservationIgnored var boardRoundID: UUID?
    /// The board's round while its drawing is sent or queued. When the round
    /// comes back to drawing, a refused drawing goes back on the board.
    @ObservationIgnored var boardSentRoundID: UUID?
    /// A correct guess of this round is being saved to the queue, so its full
    /// slots are not a refused guess.
    @ObservationIgnored var queuingCorrectGuessRoundID: UUID?
    @ObservationIgnored var markedSeenRoundIDs: Set<UUID> = []
    @ObservationIgnored var localFirstSeenAt: [UUID: Date] = [:]
    @ObservationIgnored var watchedLiveRoundIDs: Set<UUID> = []
    @ObservationIgnored var autoSentRoundIDs: Set<UUID> = []
    @ObservationIgnored var liveSnapshots: [UUID: PKDrawing] = [:]

    // The partner's drawing.
    @ObservationIgnored var replayRoundID: UUID?
    @ObservationIgnored var loadedAssetID: UUID?
    @ObservationIgnored var loadingAssetID: UUID?
    @ObservationIgnored var downloadedDrawing: PKDrawing?
    @ObservationIgnored var replayTimeline: DrawAndGuessReplayTimeline?
    @ObservationIgnored var replayClock: DrawAndGuessReplayClock? {
        didSet { sendGuessScreen() }
    }

    init(
        dependencies: GamesDependencies,
        participants: DrawAndGuessParticipants = DrawAndGuessParticipants(),
        heartbeatInterval: Duration = GamePresence.heartbeatInterval,
        tickInterval: Duration = .seconds(15),
        monotonicNow: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.dependencies = dependencies
        self.participants = participants
        self.heartbeatInterval = heartbeatInterval
        self.tickInterval = tickInterval
        self.monotonicNow = monotonicNow
        self.sleep = sleep
        partnerName = participants.partnerName
        (me, partner) = participants.players
        now = dependencies.now()
        board.onUserChange = { [weak self] drawing in
            self?.drawingChangedByUser(drawing)
        }
        if let coupleID = participants.coupleID, let room = dependencies.makeLive(coupleID) {
            attach(room)
        }
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    /// Names who is playing. Safe to call again when the names load. A change of
    /// user or couple resets what was loaded.
    func configure(participants newParticipants: DrawAndGuessParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        partnerName = newParticipants.partnerName
        (me, partner) = newParticipants.players
        if identityChanged {
            resetForNewIdentity()
        }
        if live == nil, let coupleID = newParticipants.coupleID, let room = dependencies.makeLive(coupleID) {
            attach(room)
        }
        if isRunning {
            Task { await reload() }
        }
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        syncAfterLocalChange = handler
    }

    func clearNotice() {
        notice = nil
    }

    // MARK: - Reading

    /// Re-reads the cache and the queue, then works out the phase.
    func reload() async {
        guard let userID = currentUserID else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        let document = await dependencies.cache.document(ownerUserID: userID)
        let work = await DrawAndGuessPendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        )
        let notices = await dependencies.cache.takeNotices(ownerUserID: userID)
        // A newer reload started while this one waited. It has newer data.
        guard generation == reloadGeneration, currentUserID == userID else { return }

        state = document.state
        for kept in document.hints where kept.slotIndexes.count > persistedHints[kept.roundID, default: []].count {
            persistedHints[kept.roundID] = kept.slotIndexes
        }
        if let work {
            pending = work
        }
        now = dependencies.now()
        if let stored = notices.last {
            notice = GamesNotice(stored)
        }
        recompute()
    }

    /// Reads the server's state once and caches it.
    func refresh() async {
        guard let userID = currentUserID else { return }
        guard (try? await dependencies.cache.fetchState(from: gateway, ownerUserID: userID)) == true,
              !Task.isCancelled
        else { return }
        await reload()
    }

    /// Creates the couple's game when setup is done and no game exists yet. The
    /// person who gets here first draws first.
    func startGameIfNeeded() async {
        guard phase == .preparing, !isStartingGame else { return }
        isStartingGame = true
        startFailed = false
        defer { isStartingGame = false }
        do {
            _ = try await gateway.ensureDrawAndGuessGame()
            await refresh()
        } catch {
            startFailed = true
            notice = .couldNotStartGame
        }
    }

    func retryStart() async {
        await startGameIfNeeded()
    }

    // MARK: - Working out the screen

    /// Combines the server's state and the unsent moves into the observable
    /// state, then runs the effects a new state needs.
    func recompute() {
        guard let userID = currentUserID else { return }
        let resolution = DrawAndGuessResolver(userID: userID).resolve(
            state: state,
            pending: pending,
            isPartnerDrawingLive: isPartnerDrawingLive
        )
        phase = resolution.phase
        round = resolution.round
        isWaitingToSend = resolution.isWaitingToSend
        isHeldOnPhone = isWaitingToSend && pending.hasFailedMoveAttempt
        isSendFailing = pending.lastSendFailedWhileOnline
        settings = state?.settings
        score = state?.game.flatMap { game in
            settings.map { DrawAndGuessScore(game: game, playStyle: $0.playStyle) }
        }
        choices = (phase == .chooseWord ? state?.choices : nil)?.map(DrawAndGuessWordChoice.init) ?? []
        choicesUnavailable = phase == .chooseWord && choices.isEmpty
        updatePresenceState()
        updatePartnerGuess()
        updatePartnerNextRound()
        if phase == .preparing || phase == .needsSetup {
            startFailed = startFailed && phase == .preparing
        }

        syncRoundState()
        updateSpeedBonus()
        updateReveal()
        runEffects()
    }

    /// Effects that depend on the new state. Each one guards against repeating.
    private func runEffects() {
        syncLiveRole()
        if phase == .watchingLive, live?.partnerActivity == .drawing, let round {
            watchedLiveRoundIDs.insert(round.id)
        }
        // The drawer's own drawing still goes out after the screen closed.
        sendLiveDrawingIfSolved()
        guard !isStopped else { return }
        startReplayIfNeeded()
        loadDrawingIfNeeded()
        finishReplayIfNeeded()
        sendGuessScreen()
        markSeenIfNeeded()
        if phase == .preparing, !startFailed, startTask == nil {
            startTask = Task { [weak self] in
                await self?.startGameIfNeeded()
                self?.startTask = nil
            }
        }
    }
}
