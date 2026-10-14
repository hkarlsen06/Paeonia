import Observation
import PencilKit
import QuartzCore
import SwiftUI

/// The whole Exquisite corpse flow for one person. Screens bind to the
/// observable state and call the actions. They hold no game rules.
///
/// The state comes from three places that are combined on every change: the
/// server's state in the Exquisite corpse cache (kept current by
/// `ExquisiteCorpseLiveFeed`), the couple's settings and presence in the shared
/// Games overview, and the parts and marks saved on this phone that have not been
/// sent (the pending operations). `ExquisiteCorpseResolver` turns them into
/// `phase`. Every move is written to the pending operations first, so it works
/// offline.
///
/// Files: this file holds the state and the reading. The lifecycle, the partner
/// (presence and invite), the live room, the canvas, the ideas, the strip and the
/// reveal are in the extensions.
@MainActor
@Observable
final class ExquisiteCorpseViewModel {
    // MARK: - State the screens read
    //
    // Screens only read these. The view model and its extensions write them.

    var phase: ExquisiteCorpsePhase = .loading
    /// The part the phase is about. It is this person's part while drawing and
    /// the partner's part while waiting or watching. In a reveal it is the part
    /// after the reveal, such as the next head. Nil in the other phases.
    var part: ExquisiteCorpsePartKind?
    /// The figure the phase is about, with this phone's queued part in it. During
    /// a reveal it is the finished figure.
    var figure: RemoteExquisiteCorpseFigure?
    /// The number of the figure in progress, or of the next one between figures.
    var figureNumber = 1
    /// How many figures the couple has finished.
    var figuresFinished = 0
    var settings: RemoteGameSettings?
    var partnerName: String
    var me: GamePlayer
    var partner: GamePlayer
    var partnerPresence: ExquisiteCorpsePartnerPresence = .away
    var invite: GameInviteState = .hidden
    /// A part is saved on this phone and not sent yet. It may be on its way.
    var isWaitingToSend = false
    /// A waiting part has failed to send at least once, so it really is held on
    /// this phone. Show `.gamesPendingSavedOnPhone`.
    var isHeldOnPhone = false
    /// A waiting part could not be sent although the phone is online. The waiting
    /// screen then says so and offers `retrySending()`.
    var isSendFailing = false
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: GamesNotice?
    /// The idea on the chip. Nil shows "Need an idea?".
    var idea: RemoteExquisiteCorpseIdea?
    /// The server dealt ideas for this part, so the chip can come.
    var hasIdeas = false
    /// The strip of the part above, for a body or legs drawer. It is the file once
    /// that has loaded, and the live strip from before until then.
    var strip: PKDrawing?
    var isLoadingStrip = false
    /// The last fetch of the strip failed. `retryLoadingStrip()` tries again.
    var stripLoadFailed = false

    // Watching: the partner's part, behind the folded paper.

    /// Where the partner's pen is, from 0 to 1 across their part. Nil while it is
    /// lifted.
    var partnerPen: CGPoint?
    /// The partner's strokes that reach the strip, at the canonical side.
    var partnerStrip: PKDrawing?
    /// Goes up each time the partner taps Done on the part watched here.
    var partnerDonePulse = 0
    /// The part the partner has finished and the server has not moved past yet.
    var partnerFinishedPart: ExquisiteCorpsePartKind?

    // The reveal.

    /// The finished figure with the drawings that have loaded.
    var revealContent: ExquisiteCorpseRevealContent?
    var isLoadingReveal = false
    /// A drawing of the reveal could not be fetched. `retryLoadingReveal()` tries again.
    var revealLoadFailed = false

    /// Creating the game is in progress.
    var isStartingGame = false
    var startFailed = false

    /// The drawer's canvas.
    let board = GameDrawingBoard()

    // MARK: - Dependencies

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored var gateway: any ExquisiteCorpseGateway { dependencies.exquisiteCorpseGateway }
    @ObservationIgnored var cache: any ExquisiteCorpseCaching { dependencies.exquisiteCorpseCache }
    /// This person's private stars on finished figures. The reveal and "Our creatures"
    /// share it.
    @ObservationIgnored lazy var stars = GameStars(
        source: .exquisiteCorpse(cache: dependencies.exquisiteCorpseCache),
        dependencies: dependencies
    ) { [weak self] in
        self?.currentUserID
    }
    @ObservationIgnored let heartbeatInterval: Duration
    @ObservationIgnored let tickInterval: Duration
    @ObservationIgnored let monotonicNow: @Sendable () -> TimeInterval
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    /// The square's side from the drawing screen, for the watching screen that follows it.
    @ObservationIgnored let squareMemory = GameSideMemory()
    @ObservationIgnored var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?

    // MARK: - Internal state

    @ObservationIgnored var participants: GameParticipants
    @ObservationIgnored var state: RemoteExquisiteCorpseState?
    /// The shared Games overview: the couple's settings and the partner's heartbeat.
    @ObservationIgnored var overview: RemoteGamesOverview?
    /// The idea id on the chip, by part id, as the cache keeps it.
    @ObservationIgnored var savedIdeaIDs: [UUID: String] = [:]
    @ObservationIgnored var pending = ExquisiteCorpsePendingWork.none
    @ObservationIgnored var now: Date
    @ObservationIgnored var localInviteSentAt: Date?
    @ObservationIgnored var isRunning = false
    /// The screen was open and went away. A stopped view model starts no
    /// downloads or server calls until it starts again.
    @ObservationIgnored var isStopped = false
    @ObservationIgnored var isActive = true
    @ObservationIgnored var reloadGeneration = 0
    /// The newest reload whose read is on screen.
    @ObservationIgnored var appliedReloadGeneration = 0

    @ObservationIgnored var observationTask: Task<Void, Never>?
    @ObservationIgnored var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored var tickTask: Task<Void, Never>?
    @ObservationIgnored var liveObservationTask: Task<Void, Never>?
    @ObservationIgnored var draftTask: Task<Void, Never>?
    @ObservationIgnored var startTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var stripTask: Task<Void, Never>?
    @ObservationIgnored var revealTasks: [UUID: Task<Void, Never>] = [:]

    // The canvas.
    /// The part the canvas holds.
    @ObservationIgnored var boardPartID: UUID?
    /// The part whose Done was queued from this canvas. When the part comes back
    /// as the draft (the server refused it), it goes back on the canvas.
    @ObservationIgnored var boardSentPartID: UUID?
    /// Done is reading the canvas and queuing the part. The canvas takes no touches meanwhile.
    var isFinishing = false
    @ObservationIgnored var ideaDeck: ExquisiteCorpseIdeaDeck?
    /// Saving the chip to the cache, in the order the person changed it.
    @ObservationIgnored var ideaSaveTask: Task<Void, Never>?

    // The strip above the canvas.
    @ObservationIgnored var downloadedStrip: (assetID: UUID, drawing: PKDrawing)?
    @ObservationIgnored var loadingStripAssetID: UUID?
    /// The strips the partner sent live, by part id. The latest few are kept so the
    /// hand-off from watching to drawing can show one until the file has loaded.
    @ObservationIgnored var liveStrips: [UUID: PKDrawing] = [:]
    @ObservationIgnored var liveStripOrder: [UUID] = []

    // The live room.
    /// The relay room, nil when the couple has none.
    @ObservationIgnored var live: WidgetLiveDrawing?
    /// The game's own messages in the relay room.
    @ObservationIgnored var channel: GameLiveChannel<ExquisiteCorpseLiveMessage>?
    @ObservationIgnored var penSampler = ExquisiteCorpsePenSampler()
    @ObservationIgnored weak var penCanvas: PKCanvasView?
    /// The strip last sent to the watching partner, so only a change goes out.
    @ObservationIgnored var sentStrip: (partID: UUID, signature: Int)?
    /// The part this person tapped Done on while the room was open.
    @ObservationIgnored var doneSentPartID: UUID?
    /// The part of the partner that this phone watches (waiting or watching).
    @ObservationIgnored var watchedPartID: UUID?
    /// The partner tapped Done on this part. They count as drawing until the
    /// server moves the turn, so the folded paper stays through the hand-off.
    @ObservationIgnored var partnerFinishedPartID: UUID?
    @ObservationIgnored var lastPartnerPresence: ExquisiteCorpsePartnerPresence = .away

    // The reveal.
    @ObservationIgnored var revealFigureID: UUID?
    @ObservationIgnored var revealDrawings: [ExquisiteCorpsePartKind: PKDrawing] = [:]
    @ObservationIgnored var loadingRevealAssets: Set<UUID> = []
    @ObservationIgnored var failedRevealAssets: Set<UUID> = []
    @ObservationIgnored var isContinuing = false

    init(
        dependencies: GamesDependencies,
        participants: GameParticipants = GameParticipants(),
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
        if let coupleID = participants.coupleID, let room = dependencies.makeExquisiteCorpseLive(coupleID) {
            attach(room)
        }
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    /// The partner's user id, from the game state or the shared overview.
    var partnerUserID: UUID? {
        state?.partnerUserID ?? overview?.partnerUserID
    }

    /// Names who is playing. Safe to call again when the names load. A change of
    /// user or couple resets what was loaded.
    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        partnerName = newParticipants.partnerName
        (me, partner) = newParticipants.players
        if identityChanged {
            resetForNewIdentity()
        }
        if live == nil, let coupleID = newParticipants.coupleID,
           let room = dependencies.makeExquisiteCorpseLive(coupleID) {
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
}
