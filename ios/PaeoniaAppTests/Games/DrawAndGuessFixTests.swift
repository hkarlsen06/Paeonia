import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// A download that waits until the test lets it finish, like a slow connection.
private final class GatedDrawingTransfer: GameDrawingTransferring, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private var started = 0

    var startedCount: Int { lock.withLock { started } }

    func open() {
        let waiting = lock.withLock {
            isOpen = true
            defer { continuations = [] }
            return continuations
        }
        waiting.forEach { $0.resume() }
    }

    func uploadDrawing(
        _: Data,
        parent _: GameUploadParent,
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
                continuations.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        return await MainActor.run { GameFixture.umbrella().dataRepresentation() }
    }
}

/// Fixes in how the Draw & Guess view model starts, loads drawings and shows results.
@MainActor
struct DrawAndGuessFixTests {
    private func environment(_ state: RemoteDrawAndGuessState) -> GamesTestEnvironment {
        GamesTestEnvironment(state: state)
    }

    private var guessing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    }

    // MARK: Startup

    @Test func aStartThatIsCancelledWhileReadingTheCacheOpensNothing() async {
        let env = environment(guessing)
        let viewModel = env.viewModel()

        let start = Task { await viewModel.start() }
        start.cancel()
        await start.value
        try? await Task.sleep(for: .milliseconds(100))

        #expect(!env.gateway.presence.contains(true))
        #expect(!env.gateway.calls.contains("load"))
    }

    // MARK: Drawing downloads

    private struct GatedSetup {
        let viewModel: DrawAndGuessViewModel
        let env: GamesTestEnvironment
        let transfer: GatedDrawingTransfer
    }

    private func viewModelWithGatedDownload() -> GatedSetup {
        let env = environment(guessing)
        let transfer = GatedDrawingTransfer()
        var dependencies = env.dependencies()
        dependencies.drawingTransfer = transfer
        let viewModel = DrawAndGuessViewModel(
            dependencies: dependencies,
            participants: GameFixture.participants,
            heartbeatInterval: .seconds(3_600),
            tickInterval: .seconds(3_600)
        )
        return GatedSetup(viewModel: viewModel, env: env, transfer: transfer)
    }

    @Test func aDownloadThatFinishesAfterTheScreenClosedWritesNoFile() async {
        let setup = viewModelWithGatedDownload()
        let (viewModel, env, transfer) = (setup.viewModel, setup.env, setup.transfer)
        await viewModel.start()
        let started = await waitUntil { transfer.startedCount == 1 }
        #expect(started)

        viewModel.stop()
        transfer.open()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(env.drawingStore.downloadedDrawing(mediaAssetID: GameFixture.assetID) == nil)
        #expect(!viewModel.isLoadingDrawing)
    }

    @Test func aDownloadThatFinishesAfterAnotherPersonSignedInWritesNoFile() async {
        let setup = viewModelWithGatedDownload()
        let (viewModel, env, transfer) = (setup.viewModel, setup.env, setup.transfer)
        await viewModel.reload()
        let started = await waitUntil { transfer.startedCount == 1 }
        #expect(started)

        viewModel.configure(participants: GameParticipants(currentUserID: UUID(), coupleID: UUID()))
        transfer.open()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(env.drawingStore.downloadedDrawing(mediaAssetID: GameFixture.assetID) == nil)
    }

    @Test func aDownloadThatStaysOpenIsKeptForOffline() async {
        let setup = viewModelWithGatedDownload()
        let (viewModel, env, transfer) = (setup.viewModel, setup.env, setup.transfer)
        await viewModel.reload()
        _ = await waitUntil { transfer.startedCount == 1 }

        transfer.open()
        let loaded = await waitUntil { viewModel.isReplayReady }

        #expect(loaded)
        #expect(env.drawingStore.downloadedDrawing(mediaAssetID: GameFixture.assetID) != nil)
    }

    @Test func aGuesserWhoWatchedLiveGetsTheSentDrawingWhenTheDrawerLeaves() async throws {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let env = environment(drawingState)
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = env.viewModel(live: room)
        viewModel.configure(participants: GameFixture.participants)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        sendPartnerCanvasSnapshot(on: connection)
        viewModel.recompute()
        #expect(viewModel.phase == .watchingLive)

        await env.cache.saveState(guessing, ownerUserID: GameFixture.me)
        await viewModel.reload()
        #expect(viewModel.phase == .guessing)
        #expect(viewModel.guessSource == .live)
        #expect(env.transfer.downloads.isEmpty)

        // The drawer presses Done and leaves. The live canvas goes with them.
        connection.onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
        viewModel.recompute()

        let ready = await waitUntil { viewModel.isReplayReady }
        #expect(ready)
        #expect(env.transfer.downloads == [GameFixture.assetID])
        #expect(viewModel.guessSource == .replay)
    }

    // MARK: A refused word

    @Test func theNextRoundStartsWithTheDrawingMadeForTheRefusedWord() async {
        let nextRound = UUID()
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner, roundID: nextRound),
            round: GameFixture.round(id: nextRound, state: .drawing, drawer: GameFixture.me)
        )
        let env = environment(state)
        env.drawingStore.saveRescuedDrawing(GameFixture.umbrella().dataRepresentation(), ownerUserID: GameFixture.me)
        let viewModel = env.viewModel()

        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.board.drawing.strokes.count == 3)
        // It is this round's draft now, so closing the app does not lose it.
        #expect(env.drawingStore.draft(ownerUserID: GameFixture.me, roundID: nextRound) != nil)
        #expect(env.drawingStore.rescuedDrawing(ownerUserID: GameFixture.me) == nil)
    }

    // MARK: Unseen results

    private func awayState(oldRoundID: UUID, seenBy: Set<UUID> = []) -> RemoteDrawAndGuessState {
        let nextRound = UUID()
        return GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me, roundID: nextRound),
            round: GameFixture.round(id: nextRound, state: .drawing, drawer: GameFixture.partner),
            recentRounds: [
                GameFixture.round(
                    id: oldRoundID,
                    state: .solved,
                    drawer: GameFixture.me,
                    hasDrawing: true,
                    attempts: [("cat", false), ("umbrella", true)],
                    solveMs: 18_000,
                    resultSeenBy: seenBy
                ),
            ]
        )
    }

    @Test func aResultTheDrawerHasNotSeenComesBeforeTheRoundThatFollowedIt() {
        let oldRound = UUID()
        let resolver = DrawAndGuessResolver(userID: GameFixture.me)

        let unseen = resolver.resolve(
            state: awayState(oldRoundID: oldRound),
            pending: .none,
            isPartnerDrawingLive: false
        )
        let seen = resolver.resolve(
            state: awayState(oldRoundID: oldRound, seenBy: [GameFixture.me]),
            pending: .none,
            isPartnerDrawingLive: false
        )

        #expect(unseen.phase == .reveal)
        #expect(unseen.round?.id == oldRound)
        #expect(seen.phase == .waitingForDrawing)
        #expect(seen.round?.id != oldRound)
    }
}
