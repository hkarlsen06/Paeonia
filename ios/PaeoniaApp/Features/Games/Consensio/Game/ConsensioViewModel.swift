import Foundation
import Observation
import UIKit

/// What the partner is doing in the game, as the status lines say it.
nonisolated enum ConsensioPartnerStatus: Equatable, Sendable {
    case away
    case here
    /// On the topic list or placing their marker.
    case picking
    case guessing
    case lookingAtResult
}

/// The whole Consensio flow for one person. Screens bind to the observable
/// state and call the actions. They hold no game rules.
///
/// The state comes from three places combined on every change: the server's
/// state in the Consensio cache (kept current by `ConsensioLiveFeed`), the moves
/// saved on this phone that have not been sent (the pending operations), and what
/// this person has already seen. `ConsensioResolver` turns them into `phase`.
/// Every move is written to the pending operations first, so it works offline.
///
/// Files: this file holds the state, reading, and starting the game. The moves
/// are in `+Moves`, and the partner, the live room and the marks in `+Partner`.
@MainActor
@Observable
final class ConsensioViewModel {
    // MARK: - State the screens read

    var phase: ConsensioPhase = .loading
    var resolution = ConsensioResolution(phase: .loading)
    var game: RemoteConsensioGame?
    var me: GamePlayer
    var partner: GamePlayer
    /// How each person's marker looks: their color and their drawn mark.
    var myStyle: BoardPieceStyle
    var partnerStyle: BoardPieceStyle
    /// The topic being placed, from "Start" until "Lock it in" or back.
    var placingTopic: ConsensioTopicChoice?
    /// The row chosen on the topic list.
    var selectedChoice: ConsensioTopicChoice?
    /// "Write your own" is open, with its three fields.
    var isWritingOwn = false
    var ownSubject = ""
    var ownLeftEnd = ""
    var ownRightEnd = ""
    /// Where this person's marker is while placing or guessing. It starts in the
    /// middle when a line opens, and is nil when no line is open.
    var marker: Int?
    /// The partner's guess marker while they guess live.
    var partnerMarker: Int?
    var partnerIsTouching = false
    var partnerStatus: ConsensioPartnerStatus = .away
    var invite: GameInviteState = .hidden
    var isStartingGame = false
    var startFailure: PaeoniaFailure?
    /// The placement or guess on this phone has had a try that did not get through.
    var isHeldOnPhone = false
    /// That try failed on a working connection, so the screen offers Try again
    /// instead of talking about being offline.
    var isSendFailing = false
    var notice: GamesNotice?
    var prefersReducedMotion = false
    /// The round whose reveal reached its verdict on screen.
    @ObservationIgnored var settledRevealRoundID: UUID?

    // MARK: - Dependencies

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored var gateway: any ConsensioGateway { dependencies.consensioGateway }
    @ObservationIgnored var cache: any ConsensioCaching { dependencies.consensioCache }
    @ObservationIgnored let loops: GameScreenLoops
    @ObservationIgnored let tickInterval: Duration
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?

    // MARK: - Internal state

    @ObservationIgnored var participants: GameParticipants
    @ObservationIgnored var state: RemoteConsensioState?
    @ObservationIgnored var overview: RemoteGamesOverview?
    @ObservationIgnored var pending = ConsensioPendingWork.none
    /// Moves being saved to the queue. They show at once and drop out of here when
    /// the queue has them, so a read in between does not undo them.
    @ObservationIgnored var unsavedPlacements: [ConsensioPlacePayload] = []
    @ObservationIgnored var unsavedGuesses: [UUID: Int] = [:]
    @ObservationIgnored var unsavedSeen: Set<UUID> = []
    /// Held reveals this person stepped past to place the next marker. They play
    /// on the next visit, once the real spot is here.
    @ObservationIgnored var deferredReveals: Set<UUID> = []
    @ObservationIgnored var hasLoaded = false
    @ObservationIgnored var now: Date
    @ObservationIgnored var localInviteSentAt: Date?
    @ObservationIgnored var isRunning = false
    @ObservationIgnored var isStopped = false
    @ObservationIgnored var isActive = true
    @ObservationIgnored var reloadGate = GameReloadGate()
    /// Taps when the partner places a marker and it becomes this person's turn to guess.
    @ObservationIgnored var attentionCue = GameAttentionCue()
    @ObservationIgnored var refusedMoves: [ConsensioRefusedMove] = []
    /// The rendered marks and the keys they were rendered for.
    @ObservationIgnored var markImages: [UUID: (key: String, image: UIImage)] = [:]
    @ObservationIgnored var hasFetchedMarks = false
    /// The round the marker belongs to, so a new round starts with no marker.
    @ObservationIgnored var markerRoundID: UUID?

    @ObservationIgnored var live: WidgetLiveDrawing?
    @ObservationIgnored var liveChannel: GameLiveChannel<ConsensioLiveMessage>?
    @ObservationIgnored var lastLiveSendAt: ContinuousClock.Instant?
    @ObservationIgnored var liveSendTask: Task<Void, Never>?
    @ObservationIgnored var isTouchingMarker = false

    @ObservationIgnored var liveObservationTask: Task<Void, Never>?
    @ObservationIgnored var startTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var moveTask: Task<Void, Never>?

    init(
        dependencies: GamesDependencies,
        participants: GameParticipants = GameParticipants(),
        heartbeatInterval: Duration = GamePresence.heartbeatInterval,
        tickInterval: Duration = .seconds(15),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.dependencies = dependencies
        self.participants = participants
        self.tickInterval = tickInterval
        self.sleep = sleep
        loops = GameScreenLoops(
            kind: .consensio,
            gateway: dependencies.gateway,
            heartbeatInterval: heartbeatInterval,
            sleep: sleep
        )
        (me, partner) = participants.players
        myStyle = BoardPieceStyle(
            color: .boardGameMine,
            mark: nil,
            initial: BoardPieceStyle.initial(of: participants.currentName)
        )
        partnerStyle = BoardPieceStyle(
            color: .boardGamePartner,
            mark: nil,
            initial: BoardPieceStyle.initial(of: participants.partnerName)
        )
        now = dependencies.now()
        if let coupleID = participants.coupleID, let room = dependencies.makeConsensioLive(coupleID) {
            attach(room)
        }
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        partner.name
    }

    var round: RemoteConsensioRound? {
        resolution.round
    }

    /// The topics on the list. Empty before the server sent them, as on a fresh install offline.
    var choices: [RemoteConsensioTopic] {
        game?.choices ?? []
    }

    var isFirstTurn: Bool {
        (game?.roundCount ?? 0) == 0 && pending.placements.isEmpty
    }

    var sharedPoints: Int {
        game?.sharedPoints ?? 0
    }

    /// The first rule the topic being written breaks, once all three fields have something.
    var ownTopicIssue: ConsensioTopicIssue? {
        guard !ownSubject.isEmpty || !ownLeftEnd.isEmpty || !ownRightEnd.isEmpty else { return nil }
        return ConsensioRules.ownTopicIssue(subject: ownSubject, leftEnd: ownLeftEnd, rightEnd: ownRightEnd)
    }

    var canStart: Bool {
        isWritingOwn ? ownTopicIssue == nil && !ownSubject.isEmpty : selectedChoice != nil
    }

    var showsPlacing: Bool {
        phase == .choose && placingTopic != nil
    }

    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        (me, partner) = newParticipants.players
        if identityChanged {
            resetForNewIdentity()
        }
        updateStyles()
        if live == nil, let coupleID = newParticipants.coupleID, let room = dependencies.makeConsensioLive(coupleID) {
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

    func resetForNewIdentity() {
        attentionCue.reset()
        state = nil
        overview = nil
        game = nil
        pending = .none
        unsavedPlacements = []
        unsavedGuesses = [:]
        unsavedSeen = []
        deferredReveals = []
        refusedMoves = []
        markImages = [:]
        hasFetchedMarks = false
        hasLoaded = false
        startFailure = nil
        isStartingGame = false
        phase = .loading
        resolution = ConsensioResolution(phase: .loading)
        placingTopic = nil
        selectedChoice = nil
        isWritingOwn = false
        marker = nil
        markerRoundID = nil
        partnerMarker = nil
        partnerStatus = .away
        invite = .hidden
        localInviteSentAt = nil
        live?.stop()
        live = nil
        liveChannel = nil
    }
}
