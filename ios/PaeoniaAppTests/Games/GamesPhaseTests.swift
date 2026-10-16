import Foundation
import Testing
@testable import PaeoniaApp

/// The phase a state puts the person in, from the server's rows and the moves
/// saved on the phone.
@MainActor
struct GamesPhaseTests {
    let resolver = DrawAndGuessResolver(userID: GameFixture.me)

    func phase(
        _ state: RemoteDrawAndGuessState?,
        pending: DrawAndGuessPendingWork = .none,
        live: Bool = false
    ) -> DrawAndGuessPhase {
        resolver.resolve(state: state, pending: pending, isPartnerDrawingLive: live).phase
    }

    /// A "result seen" mark that waits on this phone for the round.
    func markingSeen(
        _ roundID: UUID = GameFixture.roundID,
        in pending: DrawAndGuessPendingWork = .none
    ) -> DrawAndGuessPendingWork {
        var pending = pending
        pending.resultsSeen.append(GameResultSeenPayload(roundID: roundID, createdAt: GameFixture.now))
        return pending
    }

    func state(
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
        #expect(phase(solved, pending: markingSeen()) == .chooseWord)

        let partnersTurn = state(
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(state: .missed, drawer: GameFixture.me, hasDrawing: true)
        )
        #expect(phase(partnersTurn, pending: markingSeen()) == .waitingForWord)
    }

    @Test func aResultTheServerSaysThisPersonSawNeverShowsAgain() {
        // A fresh install or a second phone: nothing is stored here, the server knows.
        let seenByMe = state(
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(
                state: .solved,
                drawer: GameFixture.partner,
                hasDrawing: true,
                resultSeenBy: [GameFixture.me]
            )
        )
        let seenOnlyByPartner = state(
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(
                state: .solved,
                drawer: GameFixture.partner,
                hasDrawing: true,
                resultSeenBy: [GameFixture.partner]
            )
        )
        let drawerSeenIt = state(
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(
                state: .solved,
                drawer: GameFixture.me,
                hasDrawing: true,
                resultSeenBy: [GameFixture.me]
            )
        )

        #expect(phase(seenByMe) == .chooseWord)
        #expect(phase(seenOnlyByPartner) == .reveal)
        #expect(phase(drawerSeenIt) == .waitingForWord)
    }

    @Test func anOlderUnseenResultComesFirstUntilItIsSeen() {
        let nextRound = UUID()
        func afterResult(seenBy: Set<UUID>) -> RemoteDrawAndGuessState {
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .drawing, turn: GameFixture.partner, roundID: nextRound),
                round: GameFixture.round(id: nextRound, state: .drawing, drawer: GameFixture.partner),
                recentRounds: [
                    GameFixture.round(
                        state: .solved,
                        drawer: GameFixture.me,
                        hasDrawing: true,
                        resultSeenBy: seenBy
                    ),
                ]
            )
        }

        #expect(phase(afterResult(seenBy: [])) == .reveal)
        #expect(phase(afterResult(seenBy: [GameFixture.me])) == .waitingForDrawing)
        #expect(phase(afterResult(seenBy: []), pending: markingSeen()) == .waitingForDrawing)
    }

    @Test func aQueuedReactionShowsOnTheFinishedRoundBeforeTheServerHasIt() {
        let solved = state(
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true)
        )
        var pending = DrawAndGuessPendingWork.none
        pending.reactions = [
            GameReactionPayload(roundID: GameFixture.roundID, reaction: .love, createdAt: GameFixture.now),
            GameReactionPayload(roundID: GameFixture.roundID, reaction: .wow, createdAt: GameFixture.now),
        ]

        let withReaction = resolver.resolve(state: solved, pending: pending, isPartnerDrawingLive: false)
        pending.reactions.append(
            GameReactionPayload(roundID: GameFixture.roundID, reaction: nil, createdAt: GameFixture.now)
        )
        let cleared = resolver.resolve(state: solved, pending: pending, isPartnerDrawingLive: false)

        #expect(solved.currentRound?.guesserReaction == nil)
        #expect(withReaction.round?.guesserReaction == .wow)
        #expect(cleared.round?.guesserReaction == nil)
    }

    @Test func theChoicesAreForTheDrawerOnly() {
        // The server leaves them out for the guesser. The phase never offers them either.
        let waiting = state(game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil))
        #expect(phase(waiting) == .waitingForWord)
        #expect(!phase(waiting).allowsGuessing)
    }
}
