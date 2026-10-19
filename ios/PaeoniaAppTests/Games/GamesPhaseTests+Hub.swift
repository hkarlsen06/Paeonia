import Foundation
import Testing
@testable import PaeoniaApp

/// What the Games hub shows for the same states the phase tests resolve.
extension GamesPhaseTests {
    @Test func theHubStatusFollowsWhoseTurnItIs() {
        func status(_ state: RemoteDrawAndGuessState) -> DrawAndGuessHubSummary {
            let resolution = resolver.resolve(state: state, pending: .none, isPartnerDrawingLive: false)
            return DrawAndGuessHubSummary(state: state, resolution: resolution)
        }
        let yourDraw = status(state(game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil)))
        let waiting = status(state(
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true)
        ))
        let toGuess = status(state(
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        ))
        let notStarted = status(state(game: nil))

        #expect(yourDraw.status == .yourTurnToDraw)
        #expect(waiting.status == .waitingForPartner)
        #expect(toGuess.status == .yourTurnToGuess)
        #expect(notStarted.status == .notStarted)
        #expect(notStarted.score == nil)
        #expect(yourDraw.score == .against(mine: 8, partner: 5))
    }

    private func revealHubStatus(
        _ state: RemoteDrawAndGuessState,
        pending: DrawAndGuessPendingWork = .none
    ) -> DrawAndGuessHubSummary.Status {
        let resolution = resolver.resolve(state: state, pending: pending, isPartnerDrawingLive: false)
        #expect(resolution.phase == .reveal)
        return DrawAndGuessHubSummary(state: state, resolution: resolution).status
    }

    /// A finished round this phone has not shown, and the round that followed it.
    private func afterUnseenResult(
        game: DrawAndGuessGameState,
        turn: UUID,
        nextDrawer: UUID,
        oldDrawer: UUID
    ) -> RemoteDrawAndGuessState {
        let nextRound = UUID()
        return GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: game, turn: turn, roundID: nextRound),
            round: GameFixture.round(id: nextRound, state: game == .drawing ? .drawing : .guessing,
                                     drawer: nextDrawer, hasDrawing: game == .guessing),
            recentRounds: [GameFixture.round(id: UUID(), state: .solved, drawer: oldDrawer, hasDrawing: true)]
        )
    }

    /// The server gives the guesser the turn while they guess. A result this phone
    /// has not shown yet must not turn that into "your turn to draw".
    @Test func theHubShowsTheTurnAfterAnUnseenResult() {
        let me = GameFixture.me
        let partner = GameFixture.partner
        let partnerSentADrawing = afterUnseenResult(game: .guessing, turn: me, nextDrawer: partner, oldDrawer: me)
        let partnerIsDrawing = afterUnseenResult(game: .drawing, turn: partner, nextDrawer: partner, oldDrawer: me)
        let iSentADrawing = afterUnseenResult(game: .guessing, turn: partner, nextDrawer: me, oldDrawer: partner)
        let iGuessedIt = state(
            game: GameFixture.game(state: .choosingWord, turn: me, roundID: nil),
            round: GameFixture.round(state: .solved, drawer: partner, hasDrawing: true)
        )
        let partnerGuessedIt = state(
            game: GameFixture.game(state: .choosingWord, turn: partner, roundID: nil),
            round: GameFixture.round(state: .solved, drawer: me, hasDrawing: true)
        )
        // This phone guessed right and the server has not heard yet, so it still has the guesser's turn.
        let guessingHere = state(
            game: GameFixture.game(state: .guessing, turn: me),
            round: GameFixture.round(state: .guessing, drawer: partner, hasDrawing: true)
        )
        var unsentCorrectGuess = DrawAndGuessPendingWork.none
        unsentCorrectGuess.guesses = [
            GameGuessPayload(
                id: UUID(), roundID: GameFixture.roundID, guess: "umbrella", isCorrect: true, createdAt: GameFixture.now
            )
        ]

        #expect(revealHubStatus(partnerSentADrawing) == .yourTurnToGuess)
        #expect(revealHubStatus(partnerIsDrawing) == .partnerIsDrawing)
        #expect(revealHubStatus(iSentADrawing) == .waitingForPartner)
        #expect(revealHubStatus(iGuessedIt) == .yourTurnToDraw)
        #expect(revealHubStatus(partnerGuessedIt) == .waitingForPartner)
        #expect(revealHubStatus(guessingHere, pending: unsentCorrectGuess) == .yourTurnToDraw)
    }

    @Test func onlyAGameThePartnerJustOpenedCounts() {
        func opened(_ old: [GameKind], _ new: [GameKind]) -> GameKind? {
            GamesViewModel.openedPartnerGame(from: old, to: new)
        }

        #expect(opened([], [.ludo]) == .ludo)
        #expect(opened([.ludo], [.mindMeld, .ludo]) == .mindMeld)
        #expect(opened([.ludo], [.ludo]) == nil)
        #expect(opened([.ludo], []) == nil)
        // Leaving the newer of two games brings the older one to the front, but
        // the partner did not just open it.
        #expect(opened([.mindMeld, .ludo], [.ludo]) == nil)
    }
}
