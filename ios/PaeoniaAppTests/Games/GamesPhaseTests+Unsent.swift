import Foundation
import Testing
@testable import PaeoniaApp

/// Moves saved on the phone that the server has not heard yet.
extension GamesPhaseTests {
    @Test func aQueuedWordPickStartsTheRoundBeforeTheServerKnowsIt() {
        let waiting = state(game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil))
        let pick = GamePickWordPayload(
            gameID: GameFixture.gameID,
            roundID: UUID(),
            choice: .easy,
            word: "pizza",
            wordID: "en-easy-pizza",
            points: 1,
            createdAt: GameFixture.now
        )
        var pending = DrawAndGuessPendingWork.none
        pending.pick = pick

        let resolution = resolver.resolve(state: waiting, pending: pending, isPartnerDrawingLive: false)

        #expect(resolution.phase == .drawing)
        #expect(resolution.round?.word == "pizza")
        #expect(resolution.round?.isOnlyOnThisPhone == true)
        #expect(resolution.isWaitingToSend)
    }

    @Test func aQueuedDrawingMovesTheDrawerOnToWaitingForTheGuess() throws {
        let drawing = state(
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        var pending = DrawAndGuessPendingWork.none
        pending.drawings = [
            GameSubmitDrawingPayload(
                gameID: GameFixture.gameID,
                roundID: GameFixture.roundID,
                coupleID: DeveloperScenarioFixture.coupleID,
                drawingData: Data(),
                reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
                finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
            )
        ]

        #expect(phase(drawing, pending: pending) == .waitingForGuess)
    }

    @Test func aQueuedCorrectGuessSolvesTheRoundAtOnceAndAGiveUpMissesIt() {
        let guessing = state(
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
        var correct = DrawAndGuessPendingWork.none
        correct.guesses = [
            GameGuessPayload(
                id: UUID(),
                roundID: GameFixture.roundID,
                guess: "umbrella",
                isCorrect: true,
                createdAt: GameFixture.now
            )
        ]
        var wrong = DrawAndGuessPendingWork.none
        wrong.guesses = [
            GameGuessPayload(
                id: UUID(),
                roundID: GameFixture.roundID,
                guess: "cat",
                isCorrect: false,
                createdAt: GameFixture.now
            )
        ]
        var gaveUp = DrawAndGuessPendingWork.none
        gaveUp.giveUps = [GameGiveUpPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now)]

        let solved = resolver.resolve(state: guessing, pending: correct, isPartnerDrawingLive: false)

        #expect(solved.phase == .reveal)
        #expect(solved.round?.state == .solved)
        #expect(solved.round?.localSolvedAt == GameFixture.now)
        #expect(phase(guessing, pending: wrong) == .guessing)
        #expect(resolver.resolve(state: guessing, pending: wrong, isPartnerDrawingLive: false)
            .round?.attempts.map(\.isPending) == [true])
        #expect(phase(guessing, pending: gaveUp) == .reveal)
        // After the reveal, the next turn waits for the server to hear the guess.
        #expect(phase(guessing, pending: markingSeen(in: correct)) == .waitingToSync)
    }

    @Test func aQueuedCorrectGuessCarriesTheBonusesThePhonePromised() {
        let guessing = state(
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
        func solved(speed: Int, hints: Int, earlier: [(String, Bool)] = []) -> DrawAndGuessRoundView? {
            solvedRound(in: guessing, speed: speed, hints: hints, earlier: earlier)
        }

        let fastFirstTry = solved(speed: 2, hints: 0)
        #expect(fastFirstTry?.speedBonus == 2)
        #expect(fastFirstTry?.firstTryBonus == 1)
        #expect(fastFirstTry?.hintsUsed == 0)

        // A wrong word before the right one costs the first-try bonus.
        let secondTry = solved(speed: 1, hints: 0, earlier: [("cat", false)])
        #expect(secondTry?.speedBonus == 1)
        #expect(secondTry?.firstTryBonus == 0)

        // Any hint takes both bonuses away, whatever the claim says.
        let hinted = solved(speed: 2, hints: 2)
        #expect(hinted?.speedBonus == 0)
        #expect(hinted?.firstTryBonus == 0)
        #expect(hinted?.hintsUsed == 2)
    }

    /// The round after a correct guess waits on this phone, with the bonuses it promised.
    private func solvedRound(
        in guessing: RemoteDrawAndGuessState,
        speed: Int,
        hints: Int,
        earlier: [(String, Bool)]
    ) -> DrawAndGuessRoundView? {
        var pending = DrawAndGuessPendingWork.none
        pending.guesses = earlier.map { guess, isCorrect in
            GameGuessPayload(
                id: UUID(),
                roundID: GameFixture.roundID,
                guess: guess,
                isCorrect: isCorrect,
                createdAt: GameFixture.now
            )
        } + [
            GameGuessPayload(
                id: UUID(),
                roundID: GameFixture.roundID,
                guess: "umbrella",
                isCorrect: true,
                createdAt: GameFixture.now,
                speedBonus: speed,
                solveMs: 9_000,
                hintsUsed: hints
            ),
        ]
        return resolver.resolve(state: guessing, pending: pending, isPartnerDrawingLive: false).round
    }
}
