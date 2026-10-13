import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// A clock the test moves by hand.
private final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = GameFixture.now

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// A download that waits until the test opens it.
private final class HeldDownloadTransfer: GameDrawingTransferring, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private var started = 0

    var startedCount: Int { lock.withLock { started } }

    func open() {
        let resumed = lock.withLock {
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        resumed.forEach { $0.resume() }
    }

    func uploadDrawing( // swiftlint:disable:this function_parameter_count
        _: Data,
        gameID _: UUID,
        roundID _: UUID,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID { // swiftlint:disable:this async_without_await
        GameFixture.assetID
    }

    func downloadDrawing(mediaAssetID _: UUID) async throws -> Data {
        lock.withLock { started += 1 }
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if isOpen { return true }
                waiting.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        return await MainActor.run { GameFixture.umbrella().dataRepresentation() }
    }
}

/// Fixes from the review of the Draw & Guess view model: drawings that must
/// never be lost, screens that went away, and guesses that were refused.
@MainActor
struct DrawAndGuessHardeningTests {
    private var guessing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    }

    private var myDrawing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
    }

    /// The partner guessed it while this person was still drawing.
    private var solvedWhileIDrew: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil),
            round: GameFixture.round(state: .solved, drawer: GameFixture.me)
        )
    }

    private func type(_ word: String, into viewModel: DrawAndGuessViewModel) throws {
        for letter in word.uppercased() where letter != " " {
            let used = viewModel.slots.placedTileIDs
            let tile = try #require(viewModel.tiles.first { $0.letter == letter && !used.contains($0.id) })
            viewModel.placeTile(tile)
        }
    }

    private func queuedDrawings(_ env: GamesTestEnvironment) async -> [PKDrawing] {
        await env.queued(.submitGameDrawing).compactMap { snapshot in
            snapshot.requestData
                .flatMap { try? JSONDecoder().decode(GameSubmitDrawingPayload.self, from: $0) }
                .flatMap { try? PKDrawing(data: $0.drawingData) }
        }
    }

    private func waitForQueued(
        _ kind: SyncPendingOperationKind,
        in env: GamesTestEnvironment
    ) async -> [PendingSyncOperationSnapshot] {
        for _ in 0..<200 {
            let queued = await env.queued(kind)
            if !queued.isEmpty { return queued }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return []
    }

    // MARK: The drawer's drawing is never lost

    @Test func aDraftOfARoundThatEndedWhileTheDrawerWasAwayIsSent() async {
        let env = GamesTestEnvironment(state: solvedWhileIDrew)
        let umbrella = GameFixture.umbrella().dataRepresentation()
        env.drawingStore.saveDraft(umbrella, ownerUserID: GameFixture.me, roundID: GameFixture.roundID)
        let viewModel = env.viewModel()

        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        let queued = await waitForQueued(.submitGameDrawing, in: env)
        #expect(queued.count == 1)
        #expect(await queuedDrawings(env).first?.strokes.count == 3)
    }

    @Test func aDrawingQueuedBeforeARestartComesBackToTheCanvasWhenItIsRefused() async throws {
        let env = GamesTestEnvironment(state: myDrawing)
        let umbrella = GameFixture.umbrella().dataRepresentation()
        let payload = GameSubmitDrawingPayload(
            gameID: GameFixture.gameID,
            roundID: GameFixture.roundID,
            coupleID: DeveloperScenarioFixture.coupleID,
            drawingData: umbrella,
            reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2),
            finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 3)
        )
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
        try await env.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: operation,
                operationKind: .submitGameDrawing,
                idempotencyScope: "games",
                requestData: try JSONEncoder().encode(payload)
            )
        )
        let viewModel = env.viewModel()

        await viewModel.reload()
        #expect(viewModel.phase == .waitingForGuess)
        #expect(viewModel.board.drawing.strokes.count == 3)

        // The server refuses it for good. The handler puts it back as the draft.
        env.drawingStore.saveDraft(umbrella, ownerUserID: GameFixture.me, roundID: GameFixture.roundID)
        try await env.pending.markTerminalFailure(
            clientOperationID: operation.id,
            errorDescription: "refused",
            at: Date()
        )
        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.board.drawing.strokes.count == 3)
        // Leaving the screen keeps it.
        viewModel.saveDraftNow()
        #expect(env.drawingStore.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) != nil)
    }

    @Test func aStrokeInProgressWhenThePartnerGuessesIsSentWithTheDrawing() async {
        let env = GamesTestEnvironment(state: myDrawing)
        let viewModel = env.viewModel()
        await viewModel.reload()
        let umbrella = GameFixture.umbrella()
        viewModel.board.canvasDidLayout(side: DrawAndGuessCanvas.canonicalSide)
        viewModel.board.updateDrawing(umbrella)
        viewModel.board.setStrokeInProgress(true)

        await env.cache.saveState(solvedWhileIDrew, ownerUserID: GameFixture.me)
        await viewModel.reload()
        #expect(viewModel.phase == .reveal)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await env.queued(.submitGameDrawing).isEmpty)

        // PencilKit commits the stroke when the finger lifts.
        let finished = PKDrawing(strokes: umbrella.strokes + [umbrella.strokes[0]])
        viewModel.board.updateDrawing(finished)
        viewModel.board.setStrokeInProgress(false)

        _ = await waitForQueued(.submitGameDrawing, in: env)
        #expect(await queuedDrawings(env).first?.strokes.count == 4)
    }

    @Test func doneSendsALateEraserChangeTheCanvasDidNotReport() async {
        let env = GamesTestEnvironment(state: myDrawing)
        let viewModel = env.viewModel()
        await viewModel.reload()
        let umbrella = GameFixture.umbrella()
        let board = viewModel.board
        board.canvasDidLayout(side: DrawAndGuessCanvas.canonicalSide)
        board.updateDrawing(umbrella)
        let canvas = PKCanvasView()
        board.bindCanvasView(canvas)
        board.canvasDidApplyDrawing(revision: board.drawingRevision)
        // The pixel eraser took a stroke away without telling the board.
        canvas.drawing = PKDrawing(strokes: Array(umbrella.strokes.prefix(2)))

        await viewModel.finishDrawing()

        #expect(await queuedDrawings(env).first?.strokes.count == 2)
    }

    // MARK: Guessing

    @Test func aRefusedCorrectGuessEmptiesTheSlotsSoThePersonCanGuessAgain() async throws {
        let env = GamesTestEnvironment(state: guessing)
        let viewModel = env.viewModel()
        await viewModel.reload()

        try type("umbrella", into: viewModel)
        let queued = await waitForQueued(.submitGameGuess, in: env)
        _ = await waitUntil { viewModel.queuingCorrectGuessRoundID == nil }
        #expect(viewModel.phase == .reveal)

        let operation = try #require(queued.first)
        try await env.pending.markTerminalFailure(
            clientOperationID: operation.operation.id,
            errorDescription: "refused",
            at: Date()
        )
        await viewModel.reload()

        #expect(viewModel.phase == .guessing)
        #expect(viewModel.slots.status != .correct)
        let tile = try #require(viewModel.tiles.first)
        viewModel.placeTile(tile)
        #expect(viewModel.slots.placedTileIDs == [tile.id])
    }

    @Test func leavingDuringTheWrongGuessAnimationOpensTheSlotsAgain() async throws {
        let env = GamesTestEnvironment(state: guessing)
        // The animation never finishes on its own.
        let viewModel = env.viewModel(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        await viewModel.start()

        try type("allerbmu", into: viewModel)
        #expect(viewModel.isShowingWrongGuess)
        viewModel.stop()

        #expect(!viewModel.isShowingWrongGuess)
        await viewModel.start()
        let tile = try #require(viewModel.tiles.first)
        viewModel.placeTile(tile)
        #expect(viewModel.slots.placedTileIDs == [tile.id])
        viewModel.stop()
    }

    @Test func aFailedFirstLookRetryKeepsTheFirstLookTime() async throws {
        let env = GamesTestEnvironment(state: guessing)
        let clock = StepClock()
        var dependencies = env.dependencies()
        dependencies.now = { clock.now }
        let viewModel = DrawAndGuessViewModel(
            dependencies: dependencies,
            participants: GameFixture.participants,
            heartbeatInterval: .seconds(3_600),
            tickInterval: .seconds(3_600)
        )
        env.gateway.fail("markSeen")
        func failedLooks() -> Int { env.gateway.calls.count { $0 == "markSeen" } }

        await viewModel.reload()
        let firstFailed = await waitUntil {
            failedLooks() == 1 && !viewModel.markedSeenRoundIDs.contains(GameFixture.roundID)
        }
        #expect(firstFailed)

        clock.advance(by: 60)
        viewModel.recompute()
        _ = await waitUntil { failedLooks() == 2 }

        #expect(viewModel.speedBonusClaim(at: clock.now).solveMs == 60_000)
    }
}

/// The live room after a drop, where a canvas left over from before it is not
/// trusted, and a screen that went away or into the background.
@MainActor
struct DrawAndGuessLiveAndLifecycleTests {
    private var guessing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    }

    @Test func aLiveCanvasCountsOnlyOnceASnapshotCaughtItUp() {
        let (room, connection) = makeOfflineLiveRoom()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        #expect(!room.isPartnerCanvasCaughtUp)

        sendPartnerCanvasSnapshot(on: connection)
        #expect(room.isPartnerCanvasCaughtUp)

        // The partner comes back on a new socket after a drop the relay never saw.
        connection.onMessage?(WidgetLiveMessage(type: .joined))
        #expect(!room.isPartnerCanvasCaughtUp)
        #expect(room.partnerCanvasDrawing?.strokes.isEmpty == false)

        sendPartnerCanvasSnapshot(on: connection)
        #expect(room.isPartnerCanvasCaughtUp)
    }

    @Test func aGuesserWhoseLiveCanvasIsFromBeforeADropDownloadsTheSentDrawing() async {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let env = GamesTestEnvironment(state: drawingState)
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = env.viewModel(live: room)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        sendPartnerCanvasSnapshot(on: connection)
        viewModel.recompute()
        #expect(viewModel.phase == .watchingLive)

        // The drawer drops and comes back. Their canvas never answers, and they press Done.
        connection.onMessage?(WidgetLiveMessage(type: .joined))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner-again", role: "drawing"))
        await env.cache.saveState(guessing, ownerUserID: GameFixture.me)
        await viewModel.reload()

        let ready = await waitUntil { viewModel.isReplayReady }
        #expect(ready)
        #expect(env.transfer.downloads == [GameFixture.assetID])
    }

    // MARK: A screen that went away

    @Test func aRefreshThatAnswersAfterTheScreenClosedStartsNoDownload() async {
        let waiting = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let env = GamesTestEnvironment(state: waiting)
        let viewModel = env.viewModel()
        await viewModel.start()
        viewModel.stop()

        env.gateway.setStateToLoad(guessing)
        await viewModel.refresh()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(env.transfer.downloads.isEmpty)
        #expect(env.gateway.seenRounds.isEmpty)
    }

    @Test func aDrawingThatAppearsInTheBackgroundIsFetchedWhenTheScreenComesBack() async {
        let waiting = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let env = GamesTestEnvironment(state: waiting)
        let viewModel = env.viewModel()
        await viewModel.start()
        viewModel.scenePhaseChanged(isActive: false)

        await env.cache.saveState(guessing, ownerUserID: GameFixture.me)
        await viewModel.reload()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(env.transfer.downloads.isEmpty)

        viewModel.scenePhaseChanged(isActive: true)
        let fetched = await waitUntil { env.transfer.downloads == [GameFixture.assetID] }
        #expect(fetched)
        viewModel.stop()
    }

    @Test func aDrawingThatArrivesInTheBackgroundWaitsForTheScreenToComeBack() async {
        let env = GamesTestEnvironment(state: guessing)
        let transfer = HeldDownloadTransfer()
        var dependencies = env.dependencies()
        dependencies.drawingTransfer = transfer
        let viewModel = DrawAndGuessViewModel(
            dependencies: dependencies,
            participants: GameFixture.participants,
            heartbeatInterval: .seconds(3_600),
            tickInterval: .seconds(3_600)
        )
        await viewModel.start()
        _ = await waitUntil { transfer.startedCount == 1 }

        viewModel.scenePhaseChanged(isActive: false)
        transfer.open()
        _ = await waitUntil { !viewModel.isLoadingDrawing }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!viewModel.isReplayReady)
        #expect(env.gateway.seenRounds.isEmpty)

        viewModel.scenePhaseChanged(isActive: true)
        #expect(viewModel.isReplayReady)
        let seen = await waitUntil { env.gateway.seenRounds == [GameFixture.roundID] }
        #expect(seen)
        viewModel.stop()
    }
}
