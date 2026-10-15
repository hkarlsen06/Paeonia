import Foundation
import Testing
@testable import PaeoniaApp

/// "Past games": paging the list, and playing a finished game again.
@MainActor
struct BoardGameHistoryTests {
    private let me = UUID()
    private let partner = UUID()
    /// 39 moves. Player one wins with the last move.
    private let moves = DeveloperBoardGamesMoves.ultimateTicTacToeGame

    private func game(_ number: Int, firstUserID: UUID? = nil) -> RemoteBoardGameHistoryGame {
        RemoteBoardGameHistoryGame(
            gameNumber: number,
            firstUserID: firstUserID ?? me,
            moves: moves,
            winnerUserID: firstUserID ?? me,
            winLine: [2, 4, 6],
            stake: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 60)
        )
    }

    // MARK: Replay

    @Test func scrubbingShowsTheBoardAfterThatMove() throws {
        let model = BoardGameReplayModel<UltimateTicTacToeBoard>(game: game(1), userID: me)
        #expect(model.me == .one)
        #expect(model.moveCount == moves.count)
        #expect(model.step == 0)
        #expect(model.lastMove == nil)

        model.scrub(to: 2)
        #expect(model.board == UltimateTicTacToeBoard.replay(Array(moves.prefix(2))))
        // The second move was player two's, my partner's.
        #expect(model.lastMove == BoardMoveEvent(number: 2, move: moves[1], player: .two, isMine: false))
        #expect(model.showsOutcome == false)

        model.scrub(to: 500)
        #expect(model.step == moves.count)
        #expect(model.isAtEnd)
        #expect(model.board.outcome?.winner == .one)
        #expect(model.showsOutcome)

        model.scrub(to: -3)
        #expect(model.step == 0)
        #expect(model.board == .initial)
        #expect(model.showsOutcome == false)
    }

    @Test func myPiecesFollowWhoStartedThatGame() {
        let model = BoardGameReplayModel<UltimateTicTacToeBoard>(game: game(1, firstUserID: partner), userID: me)
        #expect(model.me == .two)
        model.scrub(to: 1)
        #expect(model.lastMove?.isMine == false)
    }

    @Test func playingRunsToTheEndAndThenShowsTheOutcome() async {
        let model = BoardGameReplayModel<UltimateTicTacToeBoard>(
            game: game(1),
            userID: me,
            sleep: { _ in await Task.yield() }
        )
        model.play()
        #expect(model.isPlaying)
        var spins = 0
        while !model.showsOutcome, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        #expect(model.isAtEnd)
        #expect(model.isPlaying == false)
        #expect(model.showsOutcome)

        // Play at the end starts over.
        model.play()
        #expect(model.step == 0)
        #expect(model.showsOutcome == false)
        model.pause()
    }

    @Test func scrubbingPausesTheReplay() {
        let model = BoardGameReplayModel<UltimateTicTacToeBoard>(game: game(1), userID: me, sleep: { _ in
            try await Task.sleep(for: .seconds(60))
        })
        model.play()
        model.scrub(to: 5)
        #expect(model.isPlaying == false)
        #expect(model.step == 5)
    }

    // MARK: List

    @Test func loadsTheFirstPageThenOlderGames() async {
        let gateway = ScriptedBoardGamesGateway()
        let first = RemoteBoardGameHistoryPage(games: [game(3), game(2)], nextBeforeGameNumber: 2)
        gateway.setHistoryPage(first, before: nil)
        gateway.setHistoryPage(RemoteBoardGameHistoryPage(games: [game(1)], nextBeforeGameNumber: nil), before: 2)
        let history = BoardGameHistoryViewModel(kind: .ultimateTicTacToe, gateway: gateway, pageSize: 2)
        history.configure(userID: me)

        await history.load()
        #expect(history.games.map(\.gameNumber) == [3, 2])
        #expect(history.hasMore)
        #expect(history.isLoading == false)

        await history.loadMoreIfNeeded(after: game(2))
        #expect(history.games.map(\.gameNumber) == [3, 2, 1])
        #expect(history.hasMore == false)
        #expect(gateway.historyRequests == [nil, 2])
        #expect(history.game(numbered: 1) != nil)
    }

    @Test func aFailedFirstReadSaysOfflineAndAnotherUserStartsOver() async {
        let gateway = ScriptedBoardGamesGateway()
        gateway.fail("loadHistory")
        let history = BoardGameHistoryViewModel(kind: .ultimateTicTacToe, gateway: gateway)
        history.configure(userID: me)
        await history.load()
        #expect(history.loadFailed)
        #expect(history.games.isEmpty)

        gateway.unfail("loadHistory")
        gateway.setHistoryPage(RemoteBoardGameHistoryPage(games: [game(1)], nextBeforeGameNumber: nil), before: nil)
        await history.load()
        #expect(history.loadFailed == false)
        #expect(history.games.count == 1)

        history.configure(userID: partner)
        #expect(history.games.isEmpty)
        #expect(history.isLoading)
    }
}
