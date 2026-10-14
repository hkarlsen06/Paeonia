import Foundation
import Testing
@testable import PaeoniaApp

/// How the Connect Four screen's view model handles the end of a game: the
/// result, an ending that was missed, "Play again" and the score.
@MainActor
struct BoardGameViewModelEndingTests {
    private typealias Fixture = BoardGameDataFixture

    private let harness = BoardGameHarness()

    /// The partner started the game and won it in seven moves, with the winning move last.
    private var partnerWon: RemoteBoardGame {
        harness.game(
            first: .partner,
            moves: Fixture.connectFourWin,
            stake: "Loser makes coffee",
            partnerWins: 1,
            gamesFinished: 1
        )
    }

    private var partnerWonResult: BoardGameResultContent {
        BoardGameResultContent(
            winner: .partner,
            playStyle: .against,
            stake: "Loser makes coffee",
            myWins: 0,
            partnerWins: 1,
            gamesFinished: 1,
            isMissedEnding: false
        )
    }

    // MARK: Result

    @Test func aFinishedGameIHaveNotSeenReplaysTheLastMoveThenShowsTheResult() async {
        let viewModel = await harness.openBoard(partnerWon)
        defer { viewModel.stop() }

        // I played second, so only the partner's winning move is new.
        #expect(harness.sleeps.waits.count == 1)
        #expect(viewModel.displayedMoves == Fixture.connectFourWin)
        #expect(viewModel.lastMove == BoardMoveEvent(number: 7, move: 0, player: .one, isMine: false))
        #expect(viewModel.board.outcome?.winner == .one)
        #expect(viewModel.showsOutcome)
        #expect(viewModel.result == partnerWonResult)
        #expect(viewModel.turnLabel == .partnerWon)
        #expect(!viewModel.canPlay)
        await harness.expectShown(game: 1, moves: 7)
    }

    @Test func reopeningAFinishedGameIHaveSeenShowsTheSettledResultWithoutReplay() async {
        let first = await harness.openBoard(partnerWon)
        await harness.expectShown(game: 1, moves: 7)
        first.stop()
        let waitsBefore = harness.sleeps.waits.count

        // Reduce Motion is off, so a game that was not settled would play its beats.
        let reopened = await harness.reopenBoard(reducedMotion: false)
        defer { reopened.stop() }

        #expect(harness.sleeps.waits.count == waitsBefore)
        #expect(reopened.displayedMoves == Fixture.connectFourWin)
        #expect(reopened.lastMove == nil)
        #expect(reopened.showsOutcome)
        #expect(reopened.result == partnerWonResult)
        #expect(reopened.turnLabel == .partnerWon)
    }

    @Test func myWinningMoveShowsTheResultWithTheTalliesAfterTheGame() async {
        // Column 0 holds three of my discs, so one more wins.
        let game = harness.game(moves: Fixture.connectFourAlmostWon)
        let viewModel = await harness.openBoard(game, shown: harness.position(6))
        defer { viewModel.stop() }

        await viewModel.play(0)

        #expect(viewModel.showsOutcome)
        #expect(viewModel.turnLabel == .youWon)
        #expect(await harness.queuedMoves() == [Fixture.move(0, on: game, expectedVersion: 7, stake: nil)])
        // The panel counts my wins up from one less than the tally it is given, so the tally
        // has to include the game that just ended.
        #expect(viewModel.result?.winner == .me)
        #expect(viewModel.result?.myWins == 1)
        #expect(viewModel.result?.gamesFinished == 1)
        #expect(viewModel.snapshot?.myWins == 1)
    }

    // MARK: Missed ending

    @Test func anEndingIMissedShowsFirstAndContinueLeadsToTheNewGame() async {
        let next = harness.game(after: partnerWon)
        // The phone last showed the finished game one move short of its end.
        let viewModel = await harness.openBoard(next, shown: harness.position(6))
        defer { viewModel.stop() }

        #expect(viewModel.isShowingMissedEnding)
        #expect(viewModel.displayedGameNumber == 1)
        #expect(viewModel.displayedMoves == Fixture.connectFourWin)
        #expect(harness.sleeps.waits.count == 1)
        #expect(viewModel.showsOutcome)
        #expect(viewModel.result?.isMissedEnding == true)
        #expect(viewModel.result?.winner == .partner)
        #expect(viewModel.result?.stake == "Loser makes coffee")
        #expect(viewModel.stakeState == .fixed("Loser makes coffee"))
        #expect(!viewModel.canPlay)
        // The hub already reports the new game, where I move first.
        #expect(viewModel.summary?.status == .yourTurn)

        viewModel.continueAfterMissedEnding()

        #expect(!viewModel.isShowingMissedEnding)
        #expect(viewModel.displayedGameNumber == 2)
        #expect(viewModel.displayedMoves.isEmpty)
        #expect(viewModel.board == .initial)
        #expect(viewModel.me == .one)
        #expect(!viewModel.showsOutcome)
        #expect(viewModel.result == nil)
        #expect(viewModel.turnLabel == .yourTurn)
        #expect(viewModel.stakeState == .writable)
        #expect(viewModel.canPlay)
        await harness.expectShown(game: 2, moves: 0)
    }

    @Test func anEndingThatArrivesAsANewGameWhileTheBoardIsOpenShowsFirst() async {
        // The board is open one move short of the end. The partner wins and starts a rematch before
        // this phone hears about it, such as while the app was in the background.
        let viewModel = await harness.openBoard(harness.game(first: .partner, moves: Fixture.connectFourAlmostWon))
        defer { viewModel.stop() }
        #expect(viewModel.displayedMoves == Fixture.connectFourAlmostWon)

        await harness.save(harness.game(after: partnerWon))
        await viewModel.reload()

        let showsEnding = await waitUntil { viewModel.isShowingMissedEnding && !viewModel.isReplaying }
        #expect(showsEnding)
        #expect(viewModel.displayedGameNumber == 1)
        #expect(viewModel.displayedMoves == Fixture.connectFourWin)
        #expect(viewModel.result?.isMissedEnding == true)
        #expect(viewModel.result?.winner == .partner)
        #expect(!viewModel.canPlay)
    }

    @Test func aRematchThePartnerStartsWhileMyResultShowsLeavesTheEndingUntilContinue() async {
        let finished = partnerWon
        let viewModel = await harness.openBoard(finished, shown: harness.position(7))
        defer { viewModel.stop() }
        #expect(viewModel.showsOutcome)
        #expect(viewModel.result == partnerWonResult)
        #expect(!viewModel.isShowingMissedEnding)

        await harness.save(harness.game(after: finished))
        await viewModel.reload()

        #expect(viewModel.isShowingMissedEnding)
        #expect(viewModel.displayedGameNumber == 1)
        #expect(viewModel.board.outcome?.winner == .one)
        #expect(viewModel.result?.isMissedEnding == true)
        #expect(viewModel.result?.winner == .partner)
        #expect(viewModel.turnLabel == .partnerWon)
        #expect(!viewModel.canPlay)
        // "Play again" has no game to start while the ending shows.
        await viewModel.rematch()
        #expect(await harness.queuedRematches().isEmpty)

        viewModel.continueAfterMissedEnding()

        #expect(!viewModel.isShowingMissedEnding)
        #expect(viewModel.displayedGameNumber == 2)
        #expect(viewModel.result == nil)
        #expect(viewModel.canPlay)
    }

    // MARK: Play again

    @Test(arguments: [BoardGameSide.me, .partner])
    func playAgainQueuesARematchAndShowsTheNewGameWithTheOtherPartnerStarting(starter: BoardGameSide) async {
        // Whoever started the game won it in seven moves.
        let iStarted = starter == .me
        let finished = harness.game(
            first: starter,
            moves: Fixture.connectFourWin,
            myWins: iStarted ? 1 : 0,
            partnerWins: iStarted ? 0 : 1,
            gamesFinished: 1
        )
        let viewModel = await harness.openBoard(finished, shown: harness.position(7))
        defer { viewModel.stop() }
        #expect(viewModel.result != nil)
        #expect(viewModel.me == (iStarted ? BoardPlayer.one : .two))

        await viewModel.rematch()

        #expect(await harness.queuedRematches() == [Fixture.rematch(of: finished)])
        #expect(await harness.queuedMoves().isEmpty)
        #expect(viewModel.displayedGameNumber == 2)
        #expect(viewModel.board == .initial)
        // The other partner starts game 2, so the player I am flips.
        let expectedPlayer: BoardPlayer = iStarted ? .two : .one
        let expectedTurn: BoardGameTurnLabel = iStarted ? .partnerTurn : .yourTurn
        let expectedStake: BoardGameStakeState = iStarted ? .hidden : .writable
        #expect(viewModel.me == expectedPlayer)
        #expect(!viewModel.showsOutcome)
        #expect(viewModel.result == nil)
        #expect(!viewModel.isShowingMissedEnding)
        #expect(viewModel.canPlay == !iStarted)
        #expect(viewModel.turnLabel == expectedTurn)
        #expect(viewModel.stakeState == expectedStake)
        await harness.expectShown(game: 2, moves: 0)
    }

    // MARK: Score

    @Test func playingAgainstEachOtherShowsEachPartnersWinsAndTogetherShowsTheGames() async {
        let game = harness.game(moves: [3, 4], myWins: 3, partnerWins: 2, draws: 1, gamesFinished: 6)
        await harness.setPlayStyle(.against)
        let viewModel = await harness.openBoard(game, shown: harness.position(2))
        defer { viewModel.stop() }
        #expect(viewModel.score == .against(mine: 3, partner: 2))
        #expect(viewModel.summary?.score == .against(mine: 3, partner: 2))

        // Switching the style changes what the capsule shows and nothing else.
        await harness.setPlayStyle(.together)
        await viewModel.reload()
        #expect(viewModel.score == .together(games: 6))
        #expect(viewModel.summary?.score == .together(games: 6))
        #expect(viewModel.displayedMoves == [3, 4])

        await harness.setPlayStyle(.against)
        await viewModel.reload()
        #expect(viewModel.score == .against(mine: 3, partner: 2))
    }

    @Test func aCoupleWithoutSettingsPlaysAgainstEachOther() async {
        let game = harness.game(moves: [3, 4], myWins: 3, partnerWins: 2, gamesFinished: 5)
        let viewModel = await harness.openBoard(game, shown: harness.position(2))
        defer { viewModel.stop() }

        #expect(viewModel.score == .against(mine: 3, partner: 2))
    }

    @Test func theResultFollowsThePlayStyleToo() async {
        await harness.setPlayStyle(.together)
        let viewModel = await harness.openBoard(partnerWon)
        defer { viewModel.stop() }

        #expect(viewModel.result?.playStyle == .together)
        #expect(viewModel.result?.score == .together(games: 1))
    }
}
