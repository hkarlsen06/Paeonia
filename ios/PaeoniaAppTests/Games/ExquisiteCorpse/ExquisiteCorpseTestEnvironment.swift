import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

// What the view model tests run on: every dependency in memory, a relay room that
// keeps what it sends, and states for the turns a person can be in.

// MARK: - Live room

/// A relay connection that keeps what the room sends instead of opening a socket,
/// and takes the partner's messages by hand. `roomMessages` are the relay's own
/// messages (`hello`, `live`, `ops`). `gameMessages` are the game's.
@MainActor
final class RecordingCorpseConnection: WidgetLiveConnection {
    private(set) var roomMessages: [WidgetLiveMessage] = []
    private(set) var gameMessages: [ExquisiteCorpseLiveMessage] = []

    init() {
        super.init(coupleID: ExquisiteCorpseFixture.couple, ticketProvider: { _ in nil })
    }

    override func start() {}

    override func stop() {}

    override func send(_ message: WidgetLiveMessage) {
        roomMessages.append(message)
    }

    override func send(gameData: Data) {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(GameLiveEnvelope<ExquisiteCorpseLiveMessage>.self, from: gameData)
        else { return }
        gameMessages.append(envelope.message)
    }

    /// Forgets what was sent so far, so a test reads only what comes next.
    func forgetSent() {
        roomMessages = []
        gameMessages = []
    }

    /// The partner's phone joins the room and says what its screen does. `role` is a
    /// `WidgetLivePresence.Role` raw value.
    func partnerJoins(role: String = "watching") {
        onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        partnerAnnounces(role: role)
    }

    func partnerAnnounces(role: String) {
        onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role))
    }

    func partnerLeaves() {
        onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
    }

    /// The partner's phone sends one of the game's messages.
    func partnerSends(_ message: ExquisiteCorpseLiveMessage) {
        guard let data = try? JSONEncoder().encode(
            GameLiveEnvelope(game: ExquisiteCorpseLiveMessage.game, message: message)
        ) else { return }
        onGameData?(data)
    }
}

// MARK: - Fakes

/// A steady clock the test moves by hand.
final class CorpseClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval = 100

    var now: TimeInterval { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

// The transfer protocol is async, and the scripted stand-in does not await.
// swiftlint:disable async_without_await

/// Uploads succeed with the fixture's asset ids. Downloads return the files a
/// test set and fail for any other asset, like a phone without a connection.
final class CorpseViewTransfer: GameDrawingTransferring, @unchecked Sendable {
    struct Missing: Error {}

    private let lock = NSLock()
    private var files: [UUID: Data] = [:]
    private var recordedDownloads: [UUID] = []

    var downloads: [UUID] { lock.withLock { recordedDownloads } }

    func setFile(_ data: Data, for assetID: UUID) {
        lock.withLock { files[assetID] = data }
    }

    func removeFile(for assetID: UUID) {
        lock.withLock { files[assetID] = nil }
    }

    func uploadDrawing(
        _: Data,
        parent: GameUploadParent,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        parent.purpose == "exquisite_corpse_strip"
            ? ExquisiteCorpseFixture.stripAssetID
            : ExquisiteCorpseFixture.drawingAssetID
    }

    func downloadDrawing(mediaAssetID: UUID) async throws -> Data {
        let data = lock.withLock {
            recordedDownloads.append(mediaAssetID)
            return files[mediaAssetID]
        }
        guard let data else { throw Missing() }
        return data
    }
}

// swiftlint:enable async_without_await

// MARK: - Environment

/// Everything an Exquisite corpse view model test needs, in memory. The viewer is
/// `ExquisiteCorpseFixture.me`. The relay room is a real `WidgetLiveDrawing` on a
/// `RecordingCorpseConnection`, set up like the game builds it.
@MainActor
final class ExquisiteCorpseTestEnvironment {
    /// The clock the view model reads. It is the clock of the shared scripted gateway,
    /// so an invite it sends reads as just sent.
    nonisolated static let now = DeveloperGamesFixture.now

    static let participants = GameParticipants(
        currentUserID: ExquisiteCorpseFixture.me,
        coupleID: ExquisiteCorpseFixture.couple,
        partnerName: "Robin",
        currentName: "Alex"
    )

    let gateway = ScriptedExquisiteCorpseGateway()
    /// The shared calls: presence and invites.
    let gamesGateway = ScriptedGamesGateway()
    let transfer = CorpseViewTransfer()
    let cache: InMemoryExquisiteCorpseCache
    let gamesCache: InMemoryGamesCache
    let pending = InMemoryPendingSyncOperationRepository()
    let drawingStore = InMemoryGameDrawingStore()
    let operations = DeveloperScenarioOperationProvider()
    let connection = RecordingCorpseConnection()
    let room: WidgetLiveDrawing
    let clock = CorpseClock()

    /// - Parameters:
    ///   - hasSettings: The couple has picked a game language.
    ///   - partnerPresent: The shared overview says the partner has the game open.
    init(
        state: RemoteExquisiteCorpseState?,
        hasSettings: Bool = true,
        partnerPresent: Bool = false,
        lastInviteAt: Date? = nil
    ) {
        cache = InMemoryExquisiteCorpseCache(state: state, ownerUserID: ExquisiteCorpseFixture.me)
        gamesCache = InMemoryGamesCache(
            overview: Self.overview(
                hasSettings: hasSettings,
                partnerPresent: partnerPresent,
                lastInviteAt: lastInviteAt
            ),
            ownerUserID: ExquisiteCorpseFixture.me
        )
        room = WidgetLiveDrawing(
            connection: connection,
            role: .present,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }

    static func overview(
        hasSettings: Bool,
        partnerPresent: Bool,
        lastInviteAt: Date?
    ) -> RemoteGamesOverview {
        let fixture = ExquisiteCorpseFixture.self
        let hasPresence = partnerPresent || lastInviteAt != nil
        return RemoteGamesOverview(
            userID: fixture.me,
            partnerUserID: fixture.partner,
            coupleID: fixture.couple,
            settings: hasSettings ? RemoteGameSettings(
                coupleID: fixture.couple,
                playStyle: .together,
                language: .en,
                updatedByUserID: fixture.me,
                createdAt: fixture.now,
                updatedAt: fixture.now
            ) : nil,
            presence: hasPresence ? [
                RemoteGamePresence(
                    kind: .exquisiteCorpse,
                    myPresent: false,
                    partnerPresent: partnerPresent,
                    lastInviteAt: lastInviteAt
                ),
            ] : []
        )
    }

    func dependencies(withRoom: Bool = true) -> GamesDependencies {
        GamesDependencies(
            gateway: gamesGateway,
            cache: gamesCache,
            pendingOperationStore: pending,
            operationProvider: operations,
            drawingStore: drawingStore,
            drawingTransfer: transfer,
            makeLive: { _ in nil },
            now: { Self.now },
            exquisiteCorpseGateway: gateway,
            exquisiteCorpseCache: cache,
            makeExquisiteCorpseLive: { [room] _ in withRoom ? room : nil }
        )
    }

    func viewModel(
        heartbeat: Duration = .seconds(3_600),
        withRoom: Bool = true
    ) -> ExquisiteCorpseViewModel {
        let clock = clock
        return ExquisiteCorpseViewModel(
            dependencies: dependencies(withRoom: withRoom),
            participants: Self.participants,
            heartbeatInterval: heartbeat,
            tickInterval: .seconds(3_600),
            monotonicNow: { clock.now }
        )
    }

    /// A view model that has read the cache, with the canvas laid out at the
    /// canonical side so drawing and Done work.
    func loadedViewModel() async -> ExquisiteCorpseViewModel {
        let viewModel = viewModel()
        await viewModel.reload()
        viewModel.board.canvasDidLayout(side: GameCanvas.canonicalSide)
        return viewModel
    }

    /// Puts a part in the queue, the way Done does.
    func queue(_ part: ExquisiteCorpseSubmitPartPayload) async throws {
        try await pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ExquisiteCorpseFixture.me,
                operation: operations.makeOperation(),
                operationKind: .exquisiteCorpseSubmitPart,
                idempotencyScope: "exquisite-corpse-part:\(part.partID.uuidString.lowercased())",
                requestData: try JSONEncoder().encode(part)
            )
        )
    }

    /// The operations still waiting, by kind.
    func queued(_ kind: SyncPendingOperationKind) async -> [PendingSyncOperationSnapshot] {
        (try? await pending.inFlightOperations(ownerUserID: ExquisiteCorpseFixture.me, kind: kind)) ?? []
    }

    /// The part payloads still waiting.
    func queuedParts() async -> [ExquisiteCorpseSubmitPartPayload] {
        await queued(.exquisiteCorpseSubmitPart).compactMap { operation in
            operation.requestData.flatMap { try? JSONDecoder().decode(ExquisiteCorpseSubmitPartPayload.self, from: $0) }
        }
    }

    /// Gives the phone the drawings of a finished figure. This person's parts are on
    /// the phone already, as the submit handler keeps them, and the partner's are
    /// files to download.
    func seedDrawings(of figure: RemoteExquisiteCorpseFigure) {
        for part in figure.parts {
            guard let assetID = part.drawingMediaAssetID else { continue }
            let data = CorpseDrawings.part(part.partIndex).dataRepresentation()
            if part.drawerUserID == ExquisiteCorpseFixture.me {
                drawingStore.saveDownloadedDrawing(data, mediaAssetID: assetID)
            } else {
                transfer.setFile(data, for: assetID)
            }
        }
    }

    /// The server moves on: its state replaces the cached one.
    func serverState(_ state: RemoteExquisiteCorpseState) async {
        await cache.saveState(state, ownerUserID: ExquisiteCorpseFixture.me)
    }
}

// MARK: - Drawings

enum CorpseDrawings {
    static func stroke(_ locations: [CGPoint]) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 1_000)),
            transform: .identity
        )
    }

    /// A vertical line at `x` from `startY` to `endY`, with a control point every 10 points.
    static func line(from startY: CGFloat, to endY: CGFloat, x: CGFloat = 50) -> PKStroke {
        let count = Int((endY - startY) / 10) + 1
        return stroke((0..<count).map { CGPoint(x: x, y: startY + CGFloat($0) * 10) })
    }

    /// Ends above the fold at 281.6, so nothing of it is in the strip.
    static var aboveFold: PKDrawing {
        PKDrawing(strokes: [line(from: 20, to: 120)])
    }

    /// Crosses the fold, so its lower end is in the strip.
    static var crossingFold: PKDrawing {
        PKDrawing(strokes: [line(from: 200, to: 310)])
    }

    /// Lies below the fold.
    static var belowFold: PKDrawing {
        PKDrawing(strokes: [line(from: 285, to: 315, x: 120)])
    }

    /// A different drawing for each part, so a test can tell the parts apart.
    static func part(_ index: Int) -> PKDrawing {
        PKDrawing(strokes: [line(from: 30, to: 90 + CGFloat(index) * 20, x: 60 + CGFloat(index) * 40)])
    }
}

// MARK: - States

extension ExquisiteCorpseFixture {
    static let ideas = [
        idea("a grandma"),
        idea("a robot"),
        idea("a very tired knight"),
    ]

    /// Figure 1: the partner drew the head and it is `me`'s turn for the body.
    static func myBodyTurn(
        ideas: [RemoteExquisiteCorpseIdea] = ExquisiteCorpseFixture.ideas
    ) -> RemoteExquisiteCorpseState {
        state(
            game: game(figure: 1, partIndex: 1, turn: me),
            current: figure(1, parts: 1),
            ideas: ideas
        )
    }

    /// Figure 2 starts with `me`, so the head is `me`'s. There is no figure yet.
    static func myHeadTurn(figure number: Int = 2, ideas: [RemoteExquisiteCorpseIdea] = ExquisiteCorpseFixture.ideas)
        -> RemoteExquisiteCorpseState {
        state(game: game(figure: number, partIndex: 0, turn: me), ideas: ideas)
    }

    /// Figure 2: `me` drew the head, the partner the body, and the legs are `me`'s.
    static func myLegsTurn(
        ideas: [RemoteExquisiteCorpseIdea] = ExquisiteCorpseFixture.ideas
    ) -> RemoteExquisiteCorpseState {
        state(
            game: game(figure: 2, partIndex: 2, turn: me),
            current: figure(2, parts: 2),
            ideas: ideas
        )
    }

    /// Figure 2: `me` drew the head and the partner draws the body.
    static func partnerBodyTurn() -> RemoteExquisiteCorpseState {
        state(game: game(figure: 2, partIndex: 1, turn: partner), current: figure(2, parts: 1))
    }

    /// Figure 1 is new and the partner draws its head.
    static func partnerHeadTurn() -> RemoteExquisiteCorpseState {
        state(game: game(figure: 1, partIndex: 0, turn: partner))
    }

    /// A finished figure `me` has not moved past. The next head belongs to whoever
    /// drew the body.
    static func unseenReveal(figure number: Int) -> RemoteExquisiteCorpseState {
        let nextTurn = starter(ofFigure: number + 1)
        return state(
            game: game(figure: number + 1, partIndex: 0, turn: nextTurn),
            recent: [figure(number, parts: 3)]
        )
    }
}
