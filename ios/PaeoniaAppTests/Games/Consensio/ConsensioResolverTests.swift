import Foundation
import Testing
@testable import PaeoniaApp

/// The phase the server's state and the moves saved on the phone put the person in.
struct ConsensioResolverTests {
    let me = UUID()
    let partner = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Fixtures

    func game(turn: UUID, rounds: Int = 1) -> RemoteConsensioGame {
        RemoteConsensioGame(
            id: UUID(),
            turnUserID: turn,
            turnStartedAt: now,
            choices: [],
            sharedPoints: 0,
            roundCount: rounds,
            version: 1,
            createdByUserID: me,
            createdAt: now,
            updatedAt: now
        )
    }

    func round(
        _ number: Int = 1,
        placer: UUID,
        spot: Int? = 40,
        guess: Int? = nil,
        seen: Bool = false
    ) -> RemoteConsensioRound {
        RemoteConsensioRound(
            id: UUID(),
            roundNumber: number,
            placerUserID: placer,
            guesserUserID: placer == me ? partner : me,
            topicID: "camping",
            language: .en,
            subject: "Camping",
            leftEnd: "Never again",
            rightEnd: "Book it now",
            spot: spot,
            placedAt: now,
            guess: guess,
            guessedAt: guess == nil ? nil : now,
            myRevealSeenAt: seen ? now : nil
        )
    }

    func state(
        game: RemoteConsensioGame?,
        current: RemoteConsensioRound? = nil,
        previous: RemoteConsensioRound? = nil
    ) -> RemoteConsensioState {
        RemoteConsensioState(
            userID: me,
            partnerUserID: partner,
            coupleID: UUID(),
            dataEpoch: "",
            game: game,
            currentRound: current,
            previousRound: previous
        )
    }

    func resolve(
        _ state: RemoteConsensioState?,
        pending: ConsensioPendingWork = .none,
        hasLoaded: Bool = true,
        deferred: Set<UUID> = []
    ) -> ConsensioResolution {
        ConsensioResolver(userID: me).resolve(
            state: state,
            hasLoaded: hasLoaded,
            isStarting: false,
            pending: pending,
            deferredReveals: deferred
        )
    }

    func placement(_ round: Int, spot: Int = 70) -> ConsensioPlacePayload {
        ConsensioPlacePayload(
            roundID: UUID(),
            roundNumber: round,
            topic: .own(subject: "Waffles", leftEnd: "No", rightEnd: "Yes"),
            spot: spot,
            createdAt: now
        )
    }

    // MARK: Before the game

    @Test func nothingReadIsLoadingAndNoGameIsStarting() {
        #expect(resolve(nil, hasLoaded: false).phase == .loading)
        #expect(resolve(nil).phase == .starting)
        #expect(resolve(state(game: nil)).phase == .starting)
    }

    @Test func aNewGameIsTheFirstPlacersTurnToChoose() {
        #expect(resolve(state(game: game(turn: me, rounds: 0))).phase == .choose)
        #expect(resolve(state(game: game(turn: partner, rounds: 0))).phase == .waitingForTopic)
    }

    // MARK: Turns

    @Test func thePartnersMarkerWaitsForMyGuess() {
        let open = round(placer: partner, spot: nil)
        let resolution = resolve(state(game: game(turn: me), current: open))
        #expect(resolution.phase == .guess)
        #expect(resolution.round?.id == open.id)
        #expect(resolution.isYourTurn)
    }

    @Test func myMarkerWaitsForTheGuess() {
        let resolution = resolve(state(game: game(turn: partner), current: round(placer: me)))
        #expect(resolution.phase == .waitingForGuess(isQueued: false))
        #expect(!resolution.isYourTurn)
    }

    @Test func aSeenGuessedRoundHandsThePlacementToItsGuesser() {
        let mine = round(placer: partner, guess: 44, seen: true)
        #expect(resolve(state(game: game(turn: me), current: mine)).phase == .choose)
        let theirs = round(placer: me, guess: 44, seen: true)
        #expect(resolve(state(game: game(turn: partner), current: theirs)).phase == .waitingForTopic)
    }

    // MARK: Reveals

    @Test func anUnseenGuessedRoundIsTheReveal() {
        let guessed = round(placer: me, spot: 70, guess: 64)
        let resolution = resolve(state(game: game(turn: partner), current: guessed))
        #expect(resolution.phase == .reveal(isHeld: false))
        #expect(resolution.round?.knownPoints == 4)
    }

    @Test func aMissedRevealComesBeforeThePartnersNextMarker() {
        let guessed = round(1, placer: me, spot: 70, guess: 64)
        let next = round(2, placer: partner, spot: nil)
        let resolution = resolve(state(game: game(turn: me, rounds: 2), current: next, previous: guessed))
        #expect(resolution.phase == .reveal(isHeld: false))
        #expect(resolution.round?.id == guessed.id)
    }

    @Test func aRevealMarkedSeenOnThePhoneMovesOn() {
        let guessed = round(placer: me, spot: 70, guess: 64)
        var pending = ConsensioPendingWork.none
        pending.seenReveals = [guessed.id]
        #expect(resolve(state(game: game(turn: partner), current: guessed), pending: pending).phase == .waitingForTopic)
    }

    @Test func aGuessOnThePhoneHoldsTheRevealUntilTheSpotIsHere() {
        let open = round(placer: partner, spot: nil)
        var pending = ConsensioPendingWork.none
        pending.guesses[open.id] = 55
        let resolution = resolve(state(game: game(turn: me), current: open), pending: pending)
        #expect(resolution.phase == .reveal(isHeld: true))
        #expect(resolution.round?.guess == 55)
        #expect(resolution.round?.knownDistance == nil)
    }

    @Test func aHeldRevealSteppedPastGoesOnToPlacing() {
        let open = round(placer: partner, spot: nil)
        var pending = ConsensioPendingWork.none
        pending.guesses[open.id] = 55
        let resolution = resolve(state(game: game(turn: me), current: open), pending: pending, deferred: [open.id])
        #expect(resolution.phase == .choose)
    }

    // MARK: Placements on the phone

    @Test func aPlacementOnThePhoneWaitsForTheGuessAsQueued() {
        var pending = ConsensioPendingWork.none
        pending.placements = [placement(1)]
        let resolution = resolve(state(game: game(turn: me, rounds: 0)), pending: pending)
        #expect(resolution.phase == .waitingForGuess(isQueued: true))
        #expect(resolution.round?.spot == 70)
        #expect(resolution.round?.roundNumber == 1)
    }

    @Test func aPlacementAfterAQueuedGuessFollowsTheHeldRevealOnceSteppedPast() {
        let open = round(1, placer: partner, spot: nil)
        var pending = ConsensioPendingWork.none
        pending.guesses[open.id] = 55
        pending.placements = [placement(2)]
        let state = state(game: game(turn: me), current: open)
        #expect(resolve(state, pending: pending).phase == .reveal(isHeld: true))
        #expect(resolve(state, pending: pending, deferred: [open.id]).phase == .waitingForGuess(isQueued: true))
    }

    @Test func aPlacementThatCanNotFollowTheServersRoundIsIgnored() {
        // The partner's marker has no guess yet, so a placement can't come after it.
        var pending = ConsensioPendingWork.none
        pending.placements = [placement(2)]
        let open = round(1, placer: partner, spot: nil)
        #expect(resolve(state(game: game(turn: me), current: open), pending: pending).phase == .guess)
    }

    @Test func aPlacementLeftFromATurnThatMovedOnShowsNowhere() {
        // Round 2 was queued here, and another phone played on to round 4 meanwhile.
        let seen = round(4, placer: partner, spot: 30, guess: 31, seen: true)
        var pending = ConsensioPendingWork.none
        pending.placements = [placement(2)]
        #expect(resolve(state(game: game(turn: me, rounds: 4), current: seen), pending: pending).phase == .choose)
        pending.placements = [placement(5)]
        #expect(resolve(state(game: game(turn: me, rounds: 4), current: seen), pending: pending).phase
            == .waitingForGuess(isQueued: true))
    }
}

// MARK: - Attention

extension ConsensioResolverTests {
    /// The partner's marker makes it my turn, named by the round, also while my last
    /// round's reveal waits. My own guess ends it, and my own marker is never my turn.
    @Test func thePartnersMarkerMakesItMyTurnUntilIGuess() {
        func turn(_ state: RemoteConsensioState, pending: ConsensioPendingWork = .none) -> String? {
            ConsensioResolver(userID: me).attention(state: state, pending: pending).turn
        }
        let revealed = round(1, placer: me, guess: 44)
        var seen = revealed
        seen.myRevealSeenAt = now
        let theirs = round(2, placer: partner, spot: nil)
        var myGuess = ConsensioPendingWork.none
        myGuess.guesses[theirs.id] = 50

        let handedOver = turn(state(game: game(turn: me), current: theirs, previous: revealed))
        #expect(handedOver != nil)
        #expect(turn(state(game: game(turn: me), current: theirs, previous: seen)) == handedOver)
        #expect(turn(state(game: game(turn: me), current: theirs), pending: myGuess) == nil)
        #expect(turn(state(game: game(turn: partner), current: round(placer: me))) == nil)
    }
}
