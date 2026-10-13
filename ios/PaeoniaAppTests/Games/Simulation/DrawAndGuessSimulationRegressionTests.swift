import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// Focused tests for the bugs the two-phone simulation found. Each one plays
/// the moves that broke on the same harness, with no random faults.
@MainActor
@Suite(.serialized)
struct DrawAndGuessSimulationRegressionTests {
    /// Runs `body` on a fresh pair of phones, with a watchdog and the log on failure.
    private func scenario(_ body: @escaping @MainActor (SimDriver) async throws -> Void) async {
        let driver = SimDriver(seed: 1, config: SimDriver.Config(faultScale: 0))
        do {
            try await SimReport.run(timeout: .seconds(60)) {
                try await driver.setUp()
                try await body(driver)
            }
        } catch {
            Issue.record("\(error)\n\(driver.log.tail())")
        }
        driver.shutDown()
    }

    /// "Continue" on the reveal waited for the "not now" request, so on a slow
    /// connection the button did nothing until the request gave up.
    @Test func continueLeavesTheRevealWithoutWaitingForTheNetwork() async throws {
        await scenario { driver in
        let (_, guesser) = try await driver.scriptRoundToReveal()
        let viewModel = try driver.require(guesser, in: .reveal)
        #expect(viewModel.savePrompt == .ask)

        guesser.network.holdRate = 1
        let continued = Task { await viewModel.continueFromReveal() }
        await driver.pump()

        #expect(viewModel.phase == .chooseWord)
        guesser.network.releaseHeld(deliverAll: true)
        await continued.value
        }
    }

    /// The partner solved the round live and started the next one while the
    /// drawer's drawing still waited in the queue. The drawer's reveal of that
    /// round ignored the queued drawing, so the phone sent the board a second
    /// time and the server refused one of the two as already sent.
    @Test func anUnseenResultCountsTheQueuedDrawingAsSent() async throws {
        let solvedByPartner = GameFixture.round(state: .solved, drawer: GameFixture.me, attempts: [("umbrella", true)])
        let partnerDraws = GameFixture.round(id: GameFixture.nextRoundID, state: .drawing, drawer: GameFixture.partner)
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner, roundID: GameFixture.nextRoundID),
            round: partnerDraws,
            recentRounds: [solvedByPartner]
        )
        var pending = DrawAndGuessPendingWork()
        pending.drawings = [
            GameSubmitDrawingPayload(
                gameID: GameFixture.gameID,
                roundID: GameFixture.roundID,
                coupleID: DeveloperScenarioFixture.coupleID,
                drawingData: GameFixture.umbrella().dataRepresentation(),
                reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
                finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
            ),
        ]

        let resolution = DrawAndGuessResolver(userID: GameFixture.me).resolve(
            state: state,
            pending: pending,
            acknowledgedRoundIDs: [],
            isPartnerDrawingLive: false
        )

        #expect(resolution.phase == .reveal)
        #expect(resolution.round?.id == GameFixture.roundID)
        #expect(resolution.round?.isDrawingSent == true)
    }

    /// The server took a word pick, but the read after it failed while the live
    /// feed was down. The pick left the queue and the screen went back to the
    /// word choice, so the drawer picked again and the server refused it.
    @Test func aMoveStaysOnScreenWhenTheReadAfterItFails() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            drawer.isFeedOutage = true
            drawer.network.failNext("load", with: .dropBefore)
            try await driver.scriptPick(drawer)

            #expect(drawer.viewModel?.phase == .drawing)
            #expect(driver.server.game?.state == .drawing)

            drawer.isFeedOutage = false
            await driver.settle()
            #expect(drawer.viewModel?.phase == .drawing)
            #expect(drawer.viewModel?.round?.id == driver.server.game?.currentRoundID)
            #expect(await drawer.pending.inFlightCount(ownerUserID: drawer.userID) == 0)
        }
    }

    /// A drawer who relaunched mid-drawing joined the room before the canvas was
    /// on screen. The partner's request for the whole canvas found no canvas and
    /// was dropped, so the partner never saw the strokes restored from the draft.
    @Test func aCanvasAskedForBeforeItWasOnScreenGoesOutOnceItIs() {
        let connection = RecordingLiveConnection()
        let live = WidgetLiveDrawing(connection: connection, role: .drawing)
        live.currentDrawing = { GameFixture.umbrella() }
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, needsCanvas: true, from: "partner", role: "watching"))
        #expect(!connection.sent.contains { $0.snapshot == true })

        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        live.attach(to: canvas)

        let snapshot = connection.sent.last { $0.snapshot == true }
        #expect(snapshot != nil)
        #expect(live.hasSentCanvasToPartner)
    }

    /// A live feed update sent before the drawer's drawing landed arrived after
    /// the phone had read the round back with the drawing. It replaced the newer
    /// state, so the solved round looked drawingless and the drawer's phone sent
    /// the board a second time.
    @Test func aLateOlderStateNeverReplacesANewerOne() async {
        let cache = InMemoryGamesCache()
        func state(hasDrawing: Bool, attempts: [(text: String, correct: Bool)]) -> RemoteDrawAndGuessState {
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil),
                round: GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: hasDrawing, attempts: attempts)
            )
        }
        let newer = state(hasDrawing: true, attempts: [("cat", false), ("umbrella", true)])
        await cache.saveState(newer, ownerUserID: GameFixture.me)

        await cache.saveState(state(hasDrawing: false, attempts: [("cat", false), ("umbrella", true)]), ownerUserID: GameFixture.me)
        await cache.saveState(state(hasDrawing: true, attempts: [("cat", false)]), ownerUserID: GameFixture.me)
        let ticket = await cache.beginFetch()
        let savedOlderRead = await cache.saveFetchedState(
            state(hasDrawing: false, attempts: []),
            ownerUserID: GameFixture.me,
            ticket: ticket
        )

        #expect(!savedOlderRead)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == newer)
    }

    /// The photo for a save to Memories was uploaded, then the save itself
    /// failed and the phone stayed away for a week. The server deleted the
    /// unused upload, and every retry of the save failed on the gone reservation
    /// without an end and without telling the person.
    @Test func aSaveWhosePhotoUploadWasSweptUploadsItAgain() async {
        await scenario { driver in
            let (_, guesser) = try await driver.scriptRoundToReveal()
            let viewModel = try driver.require(guesser, in: .reveal)
            guesser.network.failNext("saveRound", with: .dropBefore)
            await viewModel.saveToMemories()
            await driver.pump()
            let roundID = try #require(viewModel.round?.id)
            #expect(driver.server.round(roundID)?.memoryID == nil)

            guesser.setOnline(false)
            driver.clock.advance(8 * 86_400)
            #expect(driver.server.sweepOrphanedUploads() == 1)
            await driver.settle()

            #expect(driver.server.round(roundID)?.memoryID != nil)
            #expect(await guesser.pending.inFlightCount(ownerUserID: guesser.userID) == 0)
        }
    }

    /// A drawer who relaunched after the drawing was sent had to download their
    /// own drawing for the result screen. Offline, that square stayed blank.
    @Test func theDrawersOwnSentDrawingShowsAfterARelaunchOffline() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 3)
            try await driver.scriptDone(drawer)
            await driver.settle()
            let roundID = try #require(driver.server.currentRound?.id)
            #expect(driver.server.round(roundID)?.drawingAssetID != nil)

            drawer.forceQuit(closesSocket: true)
            drawer.setOnline(false)
            drawer.launch()
            drawer.openScreen()
            await driver.pump()

            let viewModel = try driver.require(drawer, in: .waitingForGuess)
            #expect(viewModel.finalDrawing?.drawing.strokes.count == 3)
        }
    }

    /// The partner solved the round live, then the drawer's drawing landed. The
    /// read after it started, and a live feed update from before the drawing
    /// arrived while it ran. The read was thrown away because a live write came
    /// after it began, so the round looked drawingless and the drawer's phone
    /// sent the board a second time.
    @Test func aReadNewerThanALateLiveWriteIsKept() async {
        let cache = InMemoryGamesCache()
        func solved(hasDrawing: Bool) -> RemoteDrawAndGuessState {
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil),
                round: GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: hasDrawing)
            )
        }
        await cache.saveState(solved(hasDrawing: false), ownerUserID: GameFixture.me)
        let ticket = await cache.beginFetch()
        await cache.saveState(solved(hasDrawing: false), ownerUserID: GameFixture.me)

        let saved = await cache.saveFetchedState(solved(hasDrawing: true), ownerUserID: GameFixture.me, ticket: ticket)

        #expect(saved)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == solved(hasDrawing: true))
    }

    /// A reveal that opened directly, such as after a relaunch or from the
    /// developer scenario, showed an empty square until a background task read
    /// the drawing, even when the drawing was already on the phone.
    @Test func aRevealWithTheDrawingOnThePhoneShowsItAtOnce() async {
        let env = GamesTestEnvironment(
            state: GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
                round: GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true, solveMs: 4_000)
            )
        )
        env.drawingStore.saveDownloadedDrawing(GameFixture.umbrella().dataRepresentation(), mediaAssetID: GameFixture.assetID)
        let viewModel = env.viewModel()
        viewModel.configure(participants: GameFixture.participants)

        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(viewModel.finalDrawing?.drawing.strokes.isEmpty == false)
        #expect(env.transfer.downloads.isEmpty)
    }

    /// "Continue" answers the save question with "not now". Offline, that
    /// answer only lived in the open screen, so after a relaunch the choose
    /// word screen asked again.
    @Test func aNoToSavingSurvivesARelaunchOffline() async {
        await scenario { driver in
            let (_, guesser) = try await driver.scriptRoundToReveal()
            let viewModel = try driver.require(guesser, in: .reveal)
            let roundID = try #require(viewModel.round?.id)
            #expect(viewModel.savePrompt == .ask)

            guesser.setOnline(false)
            await viewModel.continueFromReveal()
            await driver.pump()
            guesser.forceQuit(closesSocket: true)
            guesser.launch()
            guesser.openScreen()
            await driver.settle()

            let reopened = try driver.require(guesser, in: .chooseWord)
            #expect(reopened.round?.id == roundID)
            #expect(reopened.savePrompt == .hidden)
        }
    }

    /// The drawer picked and drew offline while the partner changed the game
    /// language, so the server refused the old word. The drawing is kept for
    /// the next word, and the partner watching live sees it on the canvas.
    @Test func aDrawingKeptAfterARefusedWordReachesThePartnerWatchingLive() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            drawer.setOnline(false)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 3)
            try await driver.scriptDone(drawer)

            let language: GameLanguage = driver.server.settings?.language == .en ? .nb : .en
            _ = await guesser.games?.saveSettings(playStyle: .against, language: language)
            drawer.setOnline(true)
            await driver.settle()
            #expect(drawer.notices.contains(.wordRejectedDrawingKept))

            try await driver.scriptPick(drawer)
            await driver.settle()
            let drawerModel = try driver.require(drawer, in: .drawing)
            #expect(drawerModel.board.drawing.strokes.count == 3)
            let guesserModel = try driver.require(guesser, in: .watchingLive)
            #expect(guesserModel.live?.partnerCanvasDrawing?.strokes.count == 3)
        }
    }

    /// The partner guesses right while the drawer's finger is still down. The
    /// drawing goes out once that stroke ends, with the stroke in it.
    @Test func aSolveDuringAStrokeSendsTheDrawingWithThatStroke() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 2)
            await driver.settle()
            let drawerModel = try driver.require(drawer, in: .drawing)
            let canvas = try #require(drawer.canvas)

            drawerModel.board.setStrokeInProgress(true)
            try await driver.scriptGuess(guesser, right: true)
            #expect(driver.server.currentRound?.state == .solved)
            #expect(driver.server.currentRound?.drawingAssetID == nil)

            var random = SimRandom(seed: 3)
            let stroke = SimStrokes.stroke(seed: &random, side: canvas.side)
            let drawing = PKDrawing(strokes: canvas.view.drawing.strokes + [stroke])
            canvas.view.drawing = drawing
            drawerModel.board.updateDrawing(drawing, undoManager: nil)
            drawerModel.board.setStrokeInProgress(false)
            await driver.settle()

            let round = try #require(driver.server.currentRound)
            let assetID = try #require(round.drawingAssetID)
            let sent = try PKDrawing(data: try #require(driver.server.assets[assetID]?.data))
            #expect(sent.strokes.count == 3)
        }
    }

    /// The drawer's app died mid-drawing, and the partner guessed it from the
    /// live canvas meanwhile. When the drawer comes back, the saved draft is
    /// the drawing the round keeps, and both reveals show it.
    @Test func aDraftFromBeforeAForceQuitIsSentWhenThePartnerSolvedMeanwhile() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 4)
            await driver.settle()
            _ = try driver.require(guesser, in: .watchingLive)

            drawer.forceQuit(closesSocket: false)
            try await driver.scriptGuess(guesser, right: true)
            await driver.settle()
            #expect(driver.server.currentRound?.state == .solved)

            drawer.launch()
            drawer.openScreen()
            await driver.settle()

            let round = try #require(driver.server.currentRound)
            let assetID = try #require(round.drawingAssetID)
            let sent = try PKDrawing(data: try #require(driver.server.assets[assetID]?.data))
            #expect(sent.strokes.count == 4)
            for phone in [drawer, guesser] {
                let model = try driver.require(phone, in: .reveal)
                #expect(model.finalDrawing?.drawing.strokes.count == 4)
            }
        }
    }

    /// The guesser solved the round live, and the guesser's app was relaunched
    /// before the drawer's drawing was sent. The live snapshot lived only in
    /// memory, so the reveal showed a blank square. It is kept on the phone
    /// now, never goes to Memories, and gives way to the sent drawing.
    @Test func aLiveSolveStillShowsTheDrawingAfterARelaunchBeforeItWasSent() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 4)
            await driver.settle()
            _ = try driver.require(guesser, in: .watchingLive)

            drawer.forceQuit(closesSocket: false)
            try await driver.scriptGuess(guesser, right: true)
            await driver.settle()
            let roundID = try #require(driver.server.currentRound?.id)
            #expect(driver.server.currentRound?.state == .solved)
            #expect(driver.server.currentRound?.drawingAssetID == nil)

            guesser.forceQuit(closesSocket: true)
            guesser.launch()
            guesser.openScreen()
            await driver.settle()

            let relaunched = try driver.require(guesser, in: .reveal)
            #expect(relaunched.finalDrawing?.drawing.strokes.count == 4)
            #expect(relaunched.submittedDrawing == nil)

            drawer.launch()
            drawer.openScreen()
            await driver.settle()

            let revealed = try driver.require(guesser, in: .reveal)
            #expect(revealed.submittedDrawing?.drawing.strokes.count == 4)
            #expect(guesser.drawingStore.liveSnapshot(ownerUserID: guesser.userID, roundID: roundID) == nil)
        }
    }
}

/// A live connection that keeps what the room sends instead of opening a socket.
@MainActor
final class RecordingLiveConnection: WidgetLiveConnection {
    private(set) var sent: [WidgetLiveMessage] = []

    init() {
        super.init(coupleID: UUID(), ticketProvider: { _ in nil })
    }

    override func start() {}

    override func stop() {}

    override func send(_ message: WidgetLiveMessage) {
        sent.append(message)
    }
}
