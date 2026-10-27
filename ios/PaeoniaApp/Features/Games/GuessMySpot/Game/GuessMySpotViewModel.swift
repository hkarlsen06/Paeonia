import Foundation
import MapKit
import Observation
import UIKit

/// What the partner is doing in the game, as the status lines say it.
nonisolated enum GuessMySpotPartnerStatus: Equatable, Sendable {
    case away
    case here
    /// Picking or checking a photo.
    case picking
    case guessing
}

/// A photo picked and not sent yet, with the spot the sender sees on the check.
struct GuessMySpotDraft: Equatable {
    /// The round the photo will make. A new pick gets a new id.
    let roundID: UUID
    let photo: GuessMySpotPreparedPhoto
    let image: UIImage
    var spot: GuessMySpotCoordinate?
    /// What Apple's maps call the spot, once looked up.
    var place: GuessMySpotPlace?
    /// The refused send this draft puts back. Its record and photo stay on the phone
    /// until this draft is sent or replaced.
    var refusedRoundID: UUID?

    var placeName: String? { place?.name }
}

/// The whole Guess my spot flow for one person. Screens bind to the observable
/// state and call the actions. They hold no game rules.
///
/// The state comes from three places combined on every change: the server's state
/// in the Guess my spot cache (kept current by `GuessMySpotLiveFeed`), the moves
/// saved on this phone that have not been sent (the pending operations), and what
/// this person has already seen. `GuessMySpotResolver` turns them into `phase`.
/// Every move is written to the pending operations first, so it works offline.
///
/// Files: this file holds the state. Reading and starting are in `+State`, the
/// moves in `+Moves`, the photos in `+Photo`, and the partner, the live room and
/// the marks in `+Partner`.
@MainActor
@Observable
final class GuessMySpotViewModel {
    // MARK: - State the screens read

    var phase: GuessMySpotPhase = .loading
    var resolution = GuessMySpotResolution(phase: .loading)
    var game: RemoteGuessMySpotGame?
    /// The couple's play style, from the shared game settings.
    var playStyle: GamePlayStyle = .together
    var me: GamePlayer
    var partner: GamePlayer
    /// How each person's pin looks: their color and their drawn mark.
    var myStyle: BoardPieceStyle
    var partnerStyle: BoardPieceStyle
    /// The photo being checked before sending.
    var draft: GuessMySpotDraft?
    /// A picked photo is being read.
    var isPreparingPhoto = false
    /// Where the check map opens when the picked photo has no location: this
    /// person's last shared position, or their phone's country.
    var draftStartArea: GuessMySpotArea?
    /// This person's guess pin while guessing.
    var guessPin: GuessMySpotCoordinate?
    /// What the partner's guess map shows while they guess live. Their pin never
    /// comes along, so the sender sees where they look, not where they tap.
    var partnerMapView: GuessMySpotLiveMapView?
    var partnerStatus: GuessMySpotPartnerStatus = .away
    var invite: GameInviteState = .hidden
    var isStartingGame = false
    var startFailure: PaeoniaFailure?
    /// The photo of `round`, once it is here.
    var roundPhoto: UIImage?
    /// The photo of `round` could not be fetched.
    var roundPhotoFailed = false
    /// The send or guess on this phone has had a try that did not get through.
    var isHeldOnPhone = false
    /// That try failed on a working connection, so the screen offers Try again
    /// instead of talking about being offline.
    var isSendFailing = false
    var notice: GamesNotice?
    /// Shown once on the picker when a picked photo can't be read.
    var pickFailed = false
    var prefersReducedMotion = false
    /// The round whose reveal reached its verdict on screen.
    @ObservationIgnored var settledRevealRoundID: UUID?

    // MARK: - Dependencies

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored var gateway: any GuessMySpotGateway { dependencies.guessMySpotGateway }
    @ObservationIgnored var cache: any GuessMySpotCaching { dependencies.guessMySpotCache }
    @ObservationIgnored let loops: GameScreenLoops
    @ObservationIgnored let tickInterval: Duration
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?

    // MARK: - Internal state

    @ObservationIgnored var participants: GameParticipants
    @ObservationIgnored var state: RemoteGuessMySpotState?
    @ObservationIgnored var overview: RemoteGamesOverview?
    @ObservationIgnored var pending = GuessMySpotPendingWork.none
    /// Moves being saved to the queue. They show at once and drop out of here when
    /// the queue has them, so a read in between does not undo them.
    @ObservationIgnored var unsavedSends: [GuessMySpotSendPayload] = []
    @ObservationIgnored var unsavedGuesses: [UUID: GuessMySpotCoordinate] = [:]
    @ObservationIgnored var unsavedSeen: Set<UUID> = []
    /// Held reveals this person stepped past to send the next photo. They play on
    /// the next visit, once the real spot is here.
    @ObservationIgnored var deferredReveals: Set<UUID> = []
    @ObservationIgnored var hasLoaded = false
    @ObservationIgnored var now: Date
    @ObservationIgnored var localInviteSentAt: Date?
    @ObservationIgnored var isRunning = false
    @ObservationIgnored var isStopped = false
    @ObservationIgnored var isActive = true
    @ObservationIgnored var reloadGate = GameReloadGate()
    /// Taps when the partner sends a photo and it becomes this person's turn to guess.
    @ObservationIgnored var attentionCue = GameAttentionCue()
    @ObservationIgnored var refusedMoves: [GuessMySpotRefusedMove] = []
    /// Refusals the person was already told about on this visit.
    @ObservationIgnored var announcedRefusals: Set<UUID> = []
    /// The rendered marks and the keys they were rendered for.
    @ObservationIgnored var markImages: [UUID: (key: String, image: UIImage)] = [:]
    @ObservationIgnored var hasFetchedMarks = false
    /// What the guess map showed when the guess locked in, and where on the screen
    /// it sat, so the reveal starts on the same view in the same place.
    @ObservationIgnored var guessMapRect: MKMapRect?
    @ObservationIgnored var guessMapFrame: CGRect?
    /// Whether the guess map is the satellite map, for the live view.
    @ObservationIgnored var guessMapSatellite = false
    /// When the live view last went out and what it showed, to send at most 30 a
    /// second and never the same view twice in a row.
    @ObservationIgnored var liveMapViewSentAt: TimeInterval = 0
    @ObservationIgnored var liveMapViewSent: GuessMySpotLiveMapView?
    /// The round the guess pin belongs to, so a new round starts with no pin.
    @ObservationIgnored var guessPinRoundID: UUID?
    /// The round `roundPhoto` belongs to, and its load.
    @ObservationIgnored var photoRoundID: UUID?
    @ObservationIgnored var photoTask: Task<Void, Never>?
    @ObservationIgnored var namingTask: Task<Void, Never>?

    @ObservationIgnored var live: WidgetLiveDrawing?
    @ObservationIgnored var liveChannel: GameLiveChannel<GuessMySpotLiveMessage>?

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
            kind: .guessMySpot,
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
        if let coupleID = participants.coupleID, let room = dependencies.makeGuessMySpotLive(coupleID) {
            attach(room)
        }
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        partner.name
    }

    var round: RemoteGuessMySpotRound? {
        resolution.round
    }

    var isFirstTurn: Bool {
        (game?.roundCount ?? 0) == 0 && pending.sends.isEmpty
    }

    var score: GuessMySpotScore {
        GuessMySpotScore(game: game, playStyle: playStyle)
    }

    var showsCheck: Bool {
        phase == .send && draft != nil
    }

    var canSend: Bool {
        showsCheck && draft?.spot != nil
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
        if live == nil, let coupleID = newParticipants.coupleID,
           let room = dependencies.makeGuessMySpotLive(coupleID) {
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
        unsavedSends = []
        unsavedGuesses = [:]
        unsavedSeen = []
        deferredReveals = []
        refusedMoves = []
        announcedRefusals = []
        markImages = [:]
        hasFetchedMarks = false
        hasLoaded = false
        startFailure = nil
        isStartingGame = false
        phase = .loading
        resolution = GuessMySpotResolution(phase: .loading)
        draft = nil
        namingTask?.cancel()
        guessPin = nil
        guessPinRoundID = nil
        partnerMapView = nil
        partnerStatus = .away
        invite = .hidden
        localInviteSentAt = nil
        photoTask?.cancel()
        photoRoundID = nil
        roundPhoto = nil
        roundPhotoFailed = false
        live?.stop()
        live = nil
        liveChannel = nil
    }
}
