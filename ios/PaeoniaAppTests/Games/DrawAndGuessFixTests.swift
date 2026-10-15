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

    @Test func continuingFromAnUnseenResultLeadsToTheRoundInProgress() async {
        let oldRound = UUID()
        let env = environment(awayState(oldRoundID: oldRound))
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(viewModel.reveal?.outcome == .partnerSolvedIt)

        await viewModel.continueFromReveal()

        #expect(viewModel.phase == .waitingForDrawing)
    }

    // MARK: Result line

    private func solvedReveal(duration: TimeInterval?, wrongGuesses: Int, hints: Int = 0) -> DrawAndGuessReveal {
        func attempt(_ text: String, correct: Bool) -> DrawAndGuessAttemptView {
            DrawAndGuessAttemptView(
                id: UUID(),
                userID: GameFixture.partner,
                text: text,
                isCorrect: correct,
                createdAt: GameFixture.now,
                isPending: false
            )
        }
        let wrong = (0..<wrongGuesses).map { attempt("wrong\($0)", correct: false) }
        return DrawAndGuessReveal(
            outcome: .partnerSolvedIt,
            word: "umbrella",
            difficulty: .medium,
            wordPoints: 2,
            speedBonus: 0,
            firstTryBonus: 0,
            hintsUsed: hints,
            personalBest: false,
            reaction: nil,
            solveDuration: duration,
            pointsForMe: 2,
            pointsForCouple: 2,
            attempts: wrong + [attempt("umbrella", correct: true)],
            isConfirmed: true
        )
    }

    private func text(_ resource: LocalizedStringResource, locale: String) -> String {
        var resource = resource
        resource.locale = Locale(identifier: locale)
        return String(localized: resource)
    }

    @Test func theDrawersResultIsOneSentenceInBothLanguages() {
        let time = DrawAndGuessReveal.spokenDuration(18)
        struct Case {
            let duration: TimeInterval?
            let wrong: Int
            let en: String
            let nb: String
        }
        let cases = [
            Case(
                duration: 18,
                wrong: 0,
                en: "Robin got it in \(time), on the first try.",
                nb: "Robin klarte det på \(time), på første forsøk."
            ),
            Case(
                duration: 18,
                wrong: 2,
                en: "Robin got it in \(time) and 3 tries.",
                nb: "Robin klarte det på \(time) og 3 forsøk."
            ),
            Case(
                duration: nil,
                wrong: 0,
                en: "Robin got it on the first try.",
                nb: "Robin klarte det på første forsøk."
            ),
            Case(duration: nil, wrong: 2, en: "Robin got it in 3 tries.", nb: "Robin klarte det på 3 forsøk."),
            // Past 10 minutes the time says more about the day than the guess.
            Case(duration: 700, wrong: 1, en: "Robin got it in 2 tries.", nb: "Robin klarte det på 2 forsøk."),
        ]
        for item in cases {
            let line = solvedReveal(duration: item.duration, wrongGuesses: item.wrong).solvedLine(partnerName: "Robin")
            #expect(text(line, locale: "en") == item.en)
            #expect(text(line, locale: "nb") == item.nb)
        }
    }

    @Test func theDrawersResultMentionsHintsInsteadOfTries() {
        let time = DrawAndGuessReveal.spokenDuration(24)
        let timed = solvedReveal(duration: 24, wrongGuesses: 3, hints: 2).solvedLine(partnerName: "Robin")
        let untimed = solvedReveal(duration: nil, wrongGuesses: 0, hints: 1).solvedLine(partnerName: "Robin")

        // The hint count is its own string in the phone's language. The sentence around it is English here.
        let twoHints = String(localized: .gamesDrawAndGuessHints(2))
        let oneHint = String(localized: .gamesDrawAndGuessHints(1))
        #expect(text(timed, locale: "en") == "Robin got it in \(time) with \(twoHints).")
        #expect(text(untimed, locale: "en") == "Robin got it with \(oneHint).")
        // The hint count is its own plural string, so each language gets its own words.
        #expect(text(.gamesDrawAndGuessHints(1), locale: "nb") == "1 hint")
        #expect(text(.gamesDrawAndGuessHints(2), locale: "nb") == "2 hint")
    }
}
