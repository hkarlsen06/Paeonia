import Foundation
import Testing
@testable import PaeoniaApp

/// The phase a state puts the person in, from the server's rows and the moves
/// saved on the phone.
struct GamesPhaseTests {
    private let resolver = DrawAndGuessResolver(userID: GameFixture.me)

    private func phase(
        _ state: RemoteDrawAndGuessState?,
        pending: DrawAndGuessPendingWork = .none,
        acknowledged: Set<UUID> = [],
        live: Bool = false
    ) -> DrawAndGuessPhase {
        resolver.resolve(
            state: state,
            pending: pending,
            acknowledgedRoundIDs: acknowledged,
            isPartnerDrawingLive: live
        ).phase
    }

    private func state(
        game: RemoteDrawAndGuessGame?,
        round: RemoteDrawAndGuessRound? = nil,
        settings: RemoteGameSettings? = GameFixture.settings()
    ) -> RemoteDrawAndGuessState {
        GameFixture.state(settings: settings, game: game, round: round, choices: GameFixture.choices)
    }

    @Test func noStateIsLoadingNoSettingsIsSetupAndNoGameIsPreparing() {
        #expect(phase(nil) == .loading)
        #expect(phase(state(game: nil, settings: nil)) == .needsSetup)
        #expect(phase(state(game: nil)) == .preparing)
    }

    @Test func aChoosingGameBelongsToTheDrawerWhoseTurnItIs() {
        let mine = state(game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil))
        let theirs = state(game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil))

        #expect(phase(mine) == .chooseWord)
        #expect(phase(theirs) == .waitingForWord)
    }

    @Test func aRoundInProgressIsDrawingWaitingWatchingOrGuessing() {
        let drawingMine = state(
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        let sentMine = state(
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true)
        )
        let drawingTheirs = state(
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let sentTheirs = state(
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )

        #expect(phase(drawingMine) == .drawing)
        #expect(phase(sentMine) == .waitingForGuess)
        #expect(phase(drawingTheirs) == .waitingForDrawing)
        #expect(phase(drawingTheirs, live: true) == .watchingLive)
        #expect(phase(sentTheirs) == .guessing)
    }

    @Test func aFinishedRoundShowsTheRevealUntilThePersonMovesOn() {
        let solved = state(
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true)
        )

        #expect(phase(solved) == .reveal)
        #expect(phase(solved, acknowledged: [GameFixture.roundID]) == .chooseWord)

        let partnersTurn = state(
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(state: .missed, drawer: GameFixture.me, hasDrawing: true)
        )
        #expect(phase(partnersTurn, acknowledged: [GameFixture.roundID]) == .waitingForWord)
    }

    @Test func theChoicesAreForTheDrawerOnly() {
        // The server leaves them out for the guesser. The phase never offers them either.
        let waiting = state(game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil))
        #expect(phase(waiting) == .waitingForWord)
        #expect(!phase(waiting).allowsGuessing)
    }

    // MARK: Unsent moves

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

        let resolution = resolver.resolve(
            state: waiting,
            pending: pending,
            acknowledgedRoundIDs: [],
            isPartnerDrawingLive: false
        )

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
            GameGuessPayload(id: UUID(), roundID: GameFixture.roundID, guess: "umbrella", isCorrect: true, createdAt: GameFixture.now)
        ]
        var wrong = DrawAndGuessPendingWork.none
        wrong.guesses = [
            GameGuessPayload(id: UUID(), roundID: GameFixture.roundID, guess: "cat", isCorrect: false, createdAt: GameFixture.now)
        ]
        var gaveUp = DrawAndGuessPendingWork.none
        gaveUp.giveUps = [GameGiveUpPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now)]

        let solved = resolver.resolve(state: guessing, pending: correct, acknowledgedRoundIDs: [], isPartnerDrawingLive: false)

        #expect(solved.phase == .reveal)
        #expect(solved.round?.state == .solved)
        #expect(solved.round?.localSolvedAt == GameFixture.now)
        #expect(phase(guessing, pending: wrong) == .guessing)
        #expect(resolver.resolve(state: guessing, pending: wrong, acknowledgedRoundIDs: [], isPartnerDrawingLive: false)
            .round?.attempts.map(\.isPending) == [true])
        #expect(phase(guessing, pending: gaveUp) == .reveal)
        // After the reveal, the next turn waits for the server to hear the guess.
        #expect(phase(guessing, pending: correct, acknowledged: [GameFixture.roundID]) == .waitingToSync)
    }

    // MARK: Hub

    @Test func theHubStatusFollowsWhoseTurnItIs() {
        func status(_ state: RemoteDrawAndGuessState) -> DrawAndGuessHubSummary {
            let resolution = resolver.resolve(
                state: state,
                pending: .none,
                acknowledgedRoundIDs: [],
                isPartnerDrawingLive: false
            )
            return DrawAndGuessHubSummary(state: state, resolution: resolution, now: GameFixture.now)
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
        let resolution = resolver.resolve(
            state: state,
            pending: pending,
            acknowledgedRoundIDs: [],
            isPartnerDrawingLive: false
        )
        #expect(resolution.phase == .reveal)
        return DrawAndGuessHubSummary(state: state, resolution: resolution, now: GameFixture.now).status
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

    @Test func theHubShowsThePartnerHereOnlyForAFreshHeartbeat() {
        let here = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            partnerIsHere: true
        )
        let resolution = resolver.resolve(state: here, pending: .none, acknowledgedRoundIDs: [], isPartnerDrawingLive: false)

        #expect(DrawAndGuessHubSummary(state: here, resolution: resolution, now: GameFixture.now).partnerIsHere)
        #expect(!DrawAndGuessHubSummary(
            state: here,
            resolution: resolution,
            now: GameFixture.now.addingTimeInterval(120)
        ).partnerIsHere)
    }
}
