import Foundation
import Observation

/// A person as the avatars show them.
nonisolated struct MindMeldPlayer: Equatable, Sendable {
    var name: String
    var photoAssetID: UUID?
}

/// What the partner is doing in the open round, as the status line says it.
nonisolated enum MindMeldPartnerStatus: Equatable, Sendable {
    case away
    case here
    case typing
    /// The partner's word is locked in. The server says so, so it survives a lost connection.
    case locked
}

extension GameParticipants {
    /// Both people as the avatars show them.
    var mindMeldPlayers: (me: MindMeldPlayer, partner: MindMeldPlayer) {
        (
            MindMeldPlayer(name: currentName, photoAssetID: currentPhotoAssetID),
            MindMeldPlayer(name: partnerName, photoAssetID: partnerPhotoAssetID)
        )
    }
}

/// The whole Mind Meld flow for one person. Screens bind to the observable
/// state and call the actions. They hold no game rules.
///
/// The state comes from three places that are combined on every change: the
/// server's state in the Mind Meld cache (kept current by `MindMeldLiveFeed`),
/// the moves saved on this phone that have not been sent (the pending
/// operations), and what this person has already seen (marked on the server, or
/// waiting in the pending operations). `MindMeldResolver` turns them into
/// `phase`. Every move is written to the pending operations first, so it works
/// offline.
///
/// Files: this file holds the state, reading, and starting a game. The
/// lifecycle, the partner and live room, and the moves are in the extensions.
@MainActor
@Observable
final class MindMeldViewModel {
    // MARK: - State the screens read
    //
    // Screens only read these. The view model and its extensions write them.

    var phase: MindMeldPhase = .loading
    /// The game and round the phase is about, with this phone's unsent moves applied.
    var resolution = MindMeldResolution(phase: .loading)
    var stats: RemoteMindMeldStats?
    var me: MindMeldPlayer
    var partner: MindMeldPlayer
    /// The word in the text field. Bind to it. A change checks the word and tells
    /// the partner whether this person is typing.
    var draft = "" {
        didSet { draftChanged() }
    }
    /// The first rule the draft breaks. Nil when it is fine or empty.
    var draftIssue: MindMeldWordIssue?
    var partnerStatus: MindMeldPartnerStatus = .away
    var invite: GameInviteState = .hidden
    /// The partner started a new game while this person was in the old one.
    /// Stays true until this person locks in or leaves.
    var showsPartnerRestartedNote = false
    /// A game is being started, restarted, or started again.
    var isStartingGame = false
    /// Why the first read or the automatic first start failed, while there is
    /// nothing to show. The screen offers `retryStart()`.
    var startFailure: PaeoniaFailure?
    var startFailed: Bool {
        startFailure != nil
    }
    /// The lock-in on this phone has had a try that did not get through.
    var isHeldOnPhone = false
    /// The round whose reveal reached its verdict on screen.
    @ObservationIgnored var settledRevealRoundID: UUID?
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: GamesNotice?
    /// The screen sets this from Reduce Motion.
    var prefersReducedMotion = false

    // MARK: - Dependencies

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored var gateway: any MindMeldGateway { dependencies.mindMeldGateway }
    @ObservationIgnored var cache: any MindMeldCaching { dependencies.mindMeldCache }
    /// The loops that run while the screen is open: heartbeat, data changes and the clock.
    @ObservationIgnored let loops: GameScreenLoops
    @ObservationIgnored let tickInterval: Duration
    /// How long the partner's "typing" lasts without a new typing message.
    @ObservationIgnored let typingTimeout: Duration
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?

    // MARK: - Internal state

    @ObservationIgnored var participants: GameParticipants
    @ObservationIgnored var state: RemoteMindMeldState?
    /// The shared Games overview: the game language, the partner's heartbeat and this person's last invite.
    @ObservationIgnored var overview: RemoteGamesOverview?
    @ObservationIgnored var pending = MindMeldPendingWork.none
    /// Words being saved to the queue. They show as locked in at once and drop out
    /// of here when the queue has them, so a read in between does not undo the lock-in.
    @ObservationIgnored var unsavedLocks: [UUID: String] = [:]
    /// A read of the server has finished.
    @ObservationIgnored var hasLoaded = false
    @ObservationIgnored var now: Date
    @ObservationIgnored var localInviteSentAt: Date?
    @ObservationIgnored var isRunning = false
    /// The screen was open and went away. A stopped view model sends no marks or
    /// starts no game until it starts again.
    @ObservationIgnored var isStopped = false
    @ObservationIgnored var isActive = true
    @ObservationIgnored var reloadGate = GameReloadGate()
    /// Taps when the partner locks in and it becomes this person's turn.
    @ObservationIgnored var attentionCue = GameAttentionCue()
    /// Refused words that no reload has shown yet.
    @ObservationIgnored var refusedWords: [MindMeldRefusedWord] = []
    /// The open round the draft belongs to.
    @ObservationIgnored var draftRoundID: UUID?
    /// Games whose ending is queued as seen because the partner started over.
    @ObservationIgnored var queuedEndSeen: Set<UUID> = []

    @ObservationIgnored var live: WidgetLiveDrawing?
    @ObservationIgnored var liveChannel: GameLiveChannel<MindMeldLiveMessage>?
    /// The round the partner said they are typing in, until it times out.
    @ObservationIgnored var partnerTypingRound: Int?
    @ObservationIgnored var sentTyping = false
    @ObservationIgnored var lastTypingSentAt: ContinuousClock.Instant?

    @ObservationIgnored var liveObservationTask: Task<Void, Never>?
    @ObservationIgnored var typingIdleTask: Task<Void, Never>?
    @ObservationIgnored var partnerTypingTask: Task<Void, Never>?
    @ObservationIgnored var startTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    /// The newest queued move. Moves are saved one after the other in the order they were made.
    @ObservationIgnored var moveTask: Task<Void, Never>?

    init(
        dependencies: GamesDependencies,
        participants: GameParticipants = GameParticipants(),
        heartbeatInterval: Duration = GamePresence.heartbeatInterval,
        tickInterval: Duration = .seconds(15),
        typingTimeout: Duration = .seconds(4),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.dependencies = dependencies
        self.participants = participants
        self.tickInterval = tickInterval
        self.typingTimeout = typingTimeout
        self.sleep = sleep
        loops = GameScreenLoops(
            kind: .mindMeld,
            gateway: dependencies.gateway,
            heartbeatInterval: heartbeatInterval,
            sleep: sleep
        )
        (me, partner) = participants.mindMeldPlayers
        now = dependencies.now()
        if let coupleID = participants.coupleID, let room = dependencies.makeMindMeldLive(coupleID) {
            attach(room)
        }
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        partner.name
    }

    var game: RemoteMindMeldGame? {
        resolution.game
    }

    var round: RemoteMindMeldRound? {
        resolution.round
    }

    var maxRounds: Int {
        game?.maxRounds ?? 10
    }

    var isFirstRound: Bool {
        openRound?.roundNumber == 1
    }

    /// Every word said in this game's revealed rounds, by match key.
    var usedWords: [String: String] {
        game?.usedWords ?? [:]
    }

    var canLockIn: Bool {
        phase == .write && draftIssue == nil && !MindMeldWord.normalized(draft).isEmpty
    }

    /// The lock-in is only saved on this phone, and a try to send it did not get through.
    var showsOfflineLine: Bool {
        isHeldOnPhone
    }

    var revealOutcome: MindMeldRevealOutcome? {
        resolution.displayOutcome
    }

    /// Names a reveal. It stays the same when "Count it" turns a near miss into a
    /// meld, so the screen does not play the reveal again.
    var revealIdentity: String {
        switch phase {
        case .reveal, .over:
            round.map { "reveal-\($0.id.uuidString.lowercased())" } ?? ""
        default:
            ""
        }
    }

    /// The round the person can still write in, or nil in the other phases.
    var openRound: RemoteMindMeldRound? {
        resolution.round.flatMap { $0.state == .open ? $0 : nil }
    }

    /// The person is in a game in play, writing or waiting.
    var isPlaying: Bool {
        switch phase {
        case .write, .waiting: true
        default: false
        }
    }

    /// Names who is playing. Safe to call again when the names load. A change of
    /// user or couple resets what was loaded.
    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        (me, partner) = newParticipants.mindMeldPlayers
        if identityChanged {
            resetForNewIdentity()
        }
        if live == nil, let coupleID = newParticipants.coupleID, let room = dependencies.makeMindMeldLive(coupleID) {
            attach(room)
            if isRunning, isActive {
                startLive()
            }
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

    /// A different person or couple: nothing loaded so far is theirs.
    func resetForNewIdentity() {
        attentionCue.reset()
        state = nil
        overview = nil
        pending = .none
        unsavedLocks = [:]
        refusedWords = []
        hasLoaded = false
        startFailure = nil
        isStartingGame = false
        phase = .loading
        resolution = MindMeldResolution(phase: .loading)
        stats = nil
        draftRoundID = nil
        draft = ""
        draftIssue = nil
        showsPartnerRestartedNote = false
        queuedEndSeen = []
        localInviteSentAt = nil
        partnerTypingRound = nil
        partnerStatus = .away
        invite = .hidden
        live?.stop()
        live = nil
        liveChannel = nil
    }
}
