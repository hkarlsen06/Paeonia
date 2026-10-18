import Observation
import SwiftUI

/// How long a board takes to show one move, so the next replayed move waits for
/// it and the outcome starts after it.
nonisolated struct BoardGameMoveTiming: Sendable {
    let mine: Duration
    let partner: Duration
    /// How long the board shows as this phone left it before the moves it
    /// missed start to play, so the person sees the board first.
    var openLeadIn: Duration = .zero
    /// The time one move takes when it depends on the move, such as a Connect
    /// Four disc that falls further. It gets the board that holds the move. Nil
    /// for a move that takes `mine` or `partner`.
    var exact: (@Sendable (BoardMoveEvent, any BoardGameRules) -> Duration?)?
}

/// One board game screen: Connect Four, Dots and Boxes or Ultimate
/// Tic-Tac-Toe. It reads the board games cache, which the live feed keeps
/// current, puts this phone's unsent moves on top (`BoardGameResolver`), and
/// plays the partner's new moves one at a time so the board can animate each.
///
/// The board on screen (`board`) can trail the game while moves replay. Input
/// waits until the replay has caught up.
@MainActor
@Observable
final class BoardGameViewModel<Board: BoardGameRules> {
    enum Phase: Equatable {
        case loading
        /// The couple has no game of this kind and it could not be started.
        case unavailable(PaeoniaFailure)
        case game
    }

    let kind: GameKind

    // MARK: Screen state

    var phase: Phase = .loading
    /// What the board shows right now.
    var board: Board = .initial
    var lastMove: BoardMoveEvent?
    /// The player this phone plays as in the game on screen.
    var me: BoardPlayer = .one
    /// The board's outcome highlight runs.
    var showsOutcome = false
    /// Set once the result panel should show.
    var result: BoardGameResultContent?
    var isResultCollapsed = false
    /// The ending of the last game, shown before the next one because this
    /// person did not see it.
    var isShowingMissedEnding = false
    var styles: BoardPieceStyles
    var meInfo: BoardGamePlayerInfo
    var partnerInfo: BoardGamePlayerInfo
    var turnLabel: BoardGameTurnLabel = .yourTurn
    var stakeState: BoardGameStakeState = .hidden
    /// The starter's stake before the first move. It goes with that move.
    var stakeDraft = ""
    /// Ludo only: the colors of the two players on this phone. Pink for me and
    /// lavender for my partner in the other games.
    var ludoColors = LudoColorPair.standard
    /// Ludo only: the color circles before this person's first move, or nil.
    var colorChoice: BoardGameColorChoice?
    var partnerStatus: BoardGamePartnerStatus = .away
    var invite: GameInviteState = .hidden
    var score: BoardGameScore?
    /// Goes up on each extra turn of mine, so the status row can say "Another turn".
    var extraTurnCount = 0
    /// A move or rematch waits on this phone after a try that did not get through.
    var isWaitingToSend = false
    /// The last try failed for a reason other than being offline.
    var failedWhileOnline = false
    /// The hidden photo of a Dots and Boxes game.
    var photo: UIImage?
    var notice: BoardGamesNotice?
    /// The open mark editor sheet.
    var markEditor: BoardMarkEditorModel?
    var partnerName: String
    var isStarting = false

    /// What the hub card shows, from the game rather than the board on screen.
    var summary: BoardGameHubSummary?

    var canPlay: Bool {
        phase == .game
            && !isShowingMissedEnding
            && !isReplaying
            && board.outcome == nil
            && board.next == me
            && displayedMovesMatchGame
    }

    var bloomSeed: String {
        "\(kind.rawValue):\(displayedGameNumber)"
    }

    // MARK: Internal state

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored let timing: BoardGameMoveTiming
    @ObservationIgnored var participants = GameParticipants()
    @ObservationIgnored var document = BoardGamesLocalDocument()
    @ObservationIgnored var overview: RemoteGamesOverview?
    @ObservationIgnored var pending: [BoardGamePendingAction] = []
    // `canPlay` reads these, so they are observed.
    var snapshot: BoardGameSnapshot<Board>?
    @ObservationIgnored var partnerUserID: UUID?
    /// The moves on screen and the game they belong to.
    var displayedGameNumber = 0
    var displayedMoves: [Int] = []
    @ObservationIgnored var hasDisplay = false
    @ObservationIgnored var replayQueue: [Int] = []
    var isReplaying = false
    @ObservationIgnored var stagedOutcomeGame: Int?
    /// When the board finishes animating `lastMove`. The outcome waits for it.
    @ObservationIgnored var lastMoveSettles: ContinuousClock.Instant?
    @ObservationIgnored var markImages: [UUID: (key: String, image: UIImage)] = [:]
    @ObservationIgnored var photoAssetID: UUID?
    @ObservationIgnored var localInviteSentAt: Date?
    /// The color this person tapped, and the game it is for. It goes with their
    /// first move of that game.
    @ObservationIgnored var colorDraft: (gameNumber: Int, color: LudoColor)?
    @ObservationIgnored var now: Date
    @ObservationIgnored var hasFailedAttempt = false
    @ObservationIgnored var reloadGate = GameReloadGate()
    /// Goes up with each move or rematch made on this phone.
    @ObservationIgnored var localActionRevision = 0
    @ObservationIgnored var localChangeSyncHandler: (@MainActor @Sendable () async -> Void)?

    @ObservationIgnored var isRunning = false
    @ObservationIgnored var isActive = true
    /// True while the board can't show moves yet, such as while Ludo's 3D scene
    /// loads. The replay waits, so the partner's move plays where it can be seen.
    @ObservationIgnored var isWaitingForBoard = false {
        didSet {
            if oldValue, !isWaitingForBoard { resumeAfterWaitingForBoard() }
        }
    }
    @ObservationIgnored var prefersReducedMotion = false
    @ObservationIgnored var replayTask: Task<Void, Never>?
    /// The replay's wait for the move it just showed. `finishMoveAnimation` ends it early.
    @ObservationIgnored var moveWait: (number: Int, task: Task<Void, Never>)?
    @ObservationIgnored var outcomeTask: Task<Void, Never>?
    @ObservationIgnored var photoTask: Task<Void, Never>?

    /// The loops that run while the screen is open: heartbeat, data changes and the clock.
    @ObservationIgnored let loops: GameScreenLoops
    @ObservationIgnored let tickInterval: Duration
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void

    init(
        kind: GameKind,
        timing: BoardGameMoveTiming,
        dependencies: GamesDependencies,
        heartbeatInterval: Duration = GamePresence.heartbeatInterval,
        tickInterval: Duration = .seconds(15),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.kind = kind
        self.timing = timing
        self.dependencies = dependencies
        self.tickInterval = tickInterval
        self.sleep = sleep
        loops = GameScreenLoops(
            kind: kind,
            gateway: dependencies.gateway,
            heartbeatInterval: heartbeatInterval,
            sleep: sleep
        )
        now = dependencies.now()
        partnerName = ""
        let mine = BoardPieceStyle(color: .boardGameMine, mark: nil, initial: "")
        let theirs = BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "")
        styles = BoardPieceStyles(one: mine, two: theirs)
        meInfo = BoardGamePlayerInfo(name: "", photoAssetID: nil, style: mine)
        partnerInfo = BoardGamePlayerInfo(name: "", photoAssetID: nil, style: theirs)
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    func configure(participants newParticipants: GameParticipants) {
        let userChanged = participants.currentUserID != newParticipants.currentUserID
        participants = newParticipants
        partnerName = newParticipants.partnerName
        if userChanged {
            resetForNewIdentity()
        }
        updatePeople()
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        localChangeSyncHandler = handler
    }

    // MARK: - Reading

    /// Re-reads the cache, the shared overview and the unsent actions, then
    /// works out the screen.
    func reload() async {
        guard let userID = currentUserID else { return }
        let reloadTicket = reloadGate.begin()
        let actionRevision = localActionRevision
        let document = await dependencies.boardGamesCache.document(ownerUserID: userID)
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        let queue = await queueState(ownerUserID: userID)
        let marks = await renderedMarks(document.marks, userID: userID, partnerID: document.state?.partnerUserID)
        // A read that began before this phone's latest move or rematch could put
        // the board from before it back, so it is dropped as well.
        guard actionRevision == localActionRevision, currentUserID == userID,
              reloadGate.apply(reloadTicket)
        else { return }
        // From here to `recompute()` nothing waits, so no other code ever sees
        // the new data half applied.
        self.document = document
        self.overview = overview
        // A failed read of the queue keeps the actions already known, so a
        // queued move never looks lost.
        if let pending = queue.pending {
            self.pending = pending.filter { $0.kind == kind }
        }
        failedWhileOnline = queue.failedWhileOnline
        hasFailedAttempt = queue.hasFailedAttempt
        markImages = marks
        updatePeople()
        recompute()
        // Only this game's open board takes its notices, so a refusal waits for
        // the screen it belongs to. A notice taken here is shown even when a newer
        // reload has started, so none is lost between two reloads.
        if isRunning {
            let notices = await dependencies.boardGamesCache.takeNotices(kind: kind, ownerUserID: userID)
            if !notices.isEmpty, currentUserID == userID, notice == nil {
                notice = .moveRejected
            }
        }
    }

    /// This person's unsent actions, and whether a try to send one failed.
    private func queueState(ownerUserID: UUID) async -> BoardGameQueueState {
        let store = dependencies.pendingOperationStore
        let owner = ownerUserID
        return await BoardGameQueueState(
            pending: BoardGamePendingWork.load(from: store, ownerUserID: owner),
            failedWhileOnline: BoardGamePendingWork.failedWhileOnline(kind: kind, from: store, ownerUserID: owner),
            hasFailedAttempt: BoardGamePendingWork.hasFailedAttempt(kind: kind, from: store, ownerUserID: owner)
        )
    }

    /// Reads the server once. A failure keeps the cache.
    func refresh() async {
        guard let userID = currentUserID else { return }
        _ = try? await dependencies.boardGamesCache.fetchState(
            from: dependencies.boardGamesGateway,
            ownerUserID: userID
        )
        _ = try? await dependencies.boardGamesCache.fetchMarks(
            from: dependencies.boardGamesGateway,
            ownerUserID: userID
        )
        await reload()
    }

    /// Works out everything the screen shows from what `reload` read.
    func recompute() {
        now = dependencies.now()
        updatePresence()
        guard let userID = currentUserID,
              let state = document.state,
              state.userID == userID
        else {
            summary = nil
            return
        }
        partnerUserID = state.partnerUserID
        guard let game = state.game(kind), let partnerID = state.partnerUserID,
              let snapshot = BoardGameResolver.resolve(
                  game,
                  pending: pending,
                  userID: userID,
                  partnerID: partnerID,
                  as: Board.self
              )
        else {
            self.snapshot = nil
            summary = BoardGameHubSummary(status: .notStarted, score: nil)
            if case .unavailable = phase {} else {
                phase = .loading
            }
            return
        }
        self.snapshot = snapshot
        // A first send says nothing, so a normal move never flashes the line.
        isWaitingToSend = snapshot.unsentCount > 0 && hasFailedAttempt
        phase = .game
        updateSummary(snapshot, userID: userID)
        // The hub reloads this model while the screen is closed. The board moves
        // only while it is on screen, so no move counts as shown unseen.
        guard isRunning, isActive else { return }
        advanceDisplay(to: snapshot, userID: userID)
        updateScreen()
    }

    var displayedMovesMatchGame: Bool {
        guard let snapshot else { return false }
        return displayedGameNumber == snapshot.gameNumber && displayedMoves == snapshot.moves
    }

    func resetForNewIdentity() {
        replayTask?.cancel()
        outcomeTask?.cancel()
        photoTask?.cancel()
        document = BoardGamesLocalDocument()
        overview = nil
        pending = []
        snapshot = nil
        partnerUserID = nil
        hasDisplay = false
        displayedMoves = []
        displayedGameNumber = 0
        replayQueue = []
        isReplaying = false
        stagedOutcomeGame = nil
        markImages = [:]
        photo = nil
        photoAssetID = nil
        localInviteSentAt = nil
        board = .initial
        lastMove = nil
        lastMoveSettles = nil
        showsOutcome = false
        result = nil
        isShowingMissedEnding = false
        stakeDraft = ""
        colorDraft = nil
        ludoColors = .standard
        colorChoice = nil
        summary = nil
        phase = .loading
    }
}

/// What `reload` reads from the queue of unsent actions.
private nonisolated struct BoardGameQueueState {
    /// Nil when the queue can't be read.
    let pending: [BoardGamePendingAction]?
    let failedWhileOnline: Bool
    let hasFailedAttempt: Bool
}
