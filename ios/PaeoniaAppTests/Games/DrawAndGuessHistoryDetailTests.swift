import Foundation
import Testing
@testable import PaeoniaApp

/// The detail of one drawing in "Our drawings": the replay, the star, and the round's numbers.
@MainActor
struct DrawAndGuessHistoryDetailTests {
    private let environment = GamesTestEnvironment(state: nil)

    private var rounds: [RemoteDrawAndGuessHistoryRound] {
        DeveloperGamesFixture.historyRounds()
    }

    // MARK: Detail

    private func detail(
        _ round: RemoteDrawAndGuessHistoryRound,
        clock: @escaping @Sendable () -> TimeInterval = { 100 }
    ) -> DrawAndGuessHistoryDetailViewModel {
        let dependencies = environment.dependencies()
        return DrawAndGuessHistoryDetailViewModel(
            round: round,
            participants: GameFixture.participants,
            stars: DrawAndGuessStars(dependencies: dependencies) { GameFixture.me },
            drawings: DrawAndGuessHistoryDrawings(
                store: dependencies.drawingStore,
                transfer: dependencies.drawingTransfer
            ),
            monotonicNow: clock
        )
    }

    @Test func theDrawingPlaysOnceFromTheStart() async throws {
        let viewModel = detail(try #require(rounds.first))

        await viewModel.load(showsAtOnce: false)

        #expect(viewModel.drawingState == .ready)
        #expect(viewModel.frames.isFinished(100) == false)
        #expect(viewModel.frames.isFinished(10_000))
        #expect(environment.transfer.downloads == [DeveloperGamesFixture.assetID])
    }

    @Test func withReduceMotionTheFinishedDrawingShowsAndPlayAgainPlaysIt() async throws {
        let viewModel = detail(try #require(rounds.first))

        await viewModel.load(showsAtOnce: true)
        #expect(viewModel.frames.isFinished(100))

        viewModel.replay()
        #expect(viewModel.frames.isFinished(100) == false)
    }

    @Test func aDrawingOnThePhoneDoesNotDownloadAgain() async throws {
        environment.drawingStore.saveDownloadedDrawing(
            DeveloperGamesFixture.umbrella().dataRepresentation(),
            mediaAssetID: DeveloperGamesFixture.assetID
        )
        let viewModel = detail(try #require(rounds.first))

        await viewModel.load(showsAtOnce: false)

        #expect(viewModel.drawingState == .ready)
        #expect(environment.transfer.downloads.isEmpty)
    }

    @Test func aDrawingThatCannotLoadFailsAndRetryLoadsIt() async throws {
        var dependencies = environment.dependencies()
        dependencies.drawingTransfer = UnavailableGameDrawingTransfer()
        let viewModel = DrawAndGuessHistoryDetailViewModel(
            round: try #require(rounds.first),
            participants: GameFixture.participants,
            stars: DrawAndGuessStars(dependencies: dependencies) { GameFixture.me },
            drawings: DrawAndGuessHistoryDrawings(
                store: dependencies.drawingStore,
                transfer: dependencies.drawingTransfer
            )
        )

        await viewModel.load(showsAtOnce: false)

        #expect(viewModel.drawingState == .failed)
    }

    @Test func holdingSpeedsTheReplayUpAndReleasingSlowsItDown() async throws {
        let viewModel = detail(try #require(rounds.first))
        await viewModel.load(showsAtOnce: false)

        viewModel.setFastForward(true)
        #expect(viewModel.isFastForwarding)

        viewModel.setFastForward(false)
        #expect(!viewModel.isFastForwarding)
    }

    @Test func showTheWholeDrawingFinishesTheReplay() async throws {
        let viewModel = detail(try #require(rounds.first))
        await viewModel.load(showsAtOnce: false)

        viewModel.showWholeDrawing()

        #expect(viewModel.frames.isFinished(100))
    }

    @Test func theDetailStarTogglesTheSharedStar() async throws {
        let round = try #require(rounds.first { !$0.starredByMe })
        let viewModel = detail(round)

        await viewModel.toggleStar()
        #expect(viewModel.isStarred)

        await viewModel.toggleStar()
        #expect(!viewModel.isStarred)
    }

    // MARK: Models

    @Test func aSolveTimePastTenMinutesIsNotShown() throws {
        let slow = try #require(rounds.first { $0.solveMs != nil })
        let tooSlow = movedHistoryRound(slow, solveMs: RemoteDrawAndGuessHistoryRound.longestShownSolveMs + 1)
        let justRight = movedHistoryRound(slow, solveMs: RemoteDrawAndGuessHistoryRound.longestShownSolveMs)

        #expect(tooSlow.shownSolveMs == nil)
        #expect(justRight.shownSolveMs == RemoteDrawAndGuessHistoryRound.longestShownSolveMs)
    }

    @Test func aMissedRoundShowsNoSolveTime() throws {
        let missed = try #require(rounds.first { !$0.isSolved })
        #expect(missed.shownSolveMs == nil)
    }

    @Test func anUnderSecondTimeReadsAsOneSecond() {
        #expect(DrawAndGuessHistoryFormat.duration(ms: 400) == DrawAndGuessHistoryFormat.duration(ms: 1_000))
    }

    @Test func theServersAnswersDecode() throws {
        let page = """
        {"rounds":[{"id":"bbbbbbbb-0000-4000-8000-000000000001","round_number":7,
        "drawer_user_id":"aaaaaaaa-0000-4000-8000-000000000001",
        "guesser_user_id":"aaaaaaaa-0000-4000-8000-000000000002","word":"cat","difficulty":"easy",
        "points":1,"state":"solved","drawing_media_asset_id":"cccccccc-0000-4000-8000-000000000001",
        "solve_ms":7500,"speed_bonus":2,"first_try_bonus":1,"hints_used":0,"attempt_count":1,
        "guesser_reaction":"love","personal_best":true,"starred_by_me":true,
        "started_at":"2026-10-12T08:00:00.000Z","ended_at":"2026-10-12T08:01:00.000Z"}],
        "next_before_round_number":null}
        """
        let decoded = try PaeoniaConvexClient.decoder.decode(RemoteDrawAndGuessHistoryPage.self, from: Data(page.utf8))
        #expect(decoded.rounds.first?.guesserReaction == .love)
        #expect(decoded.rounds.first?.solveMs == 7_500)
        #expect(decoded.rounds.first?.starredByMe == true)
        #expect(decoded.nextBeforeRoundNumber == nil)

        let records = """
        {"partners":[{"user_id":"aaaaaaaa-0000-4000-8000-000000000001","solves":0,"first_try_solves":0,
        "average_solve_ms":null,"fastest_solve_ms":null,"fastest_solve_word":null,"drawings_solved":0}]}
        """
        let decodedRecords = try PaeoniaConvexClient.decoder.decode(
            RemoteDrawAndGuessRecords.self,
            from: Data(records.utf8)
        )
        #expect(decodedRecords.partners.first?.averageSolveMs == nil)
    }
}
