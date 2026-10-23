import Foundation
import Testing
@testable import PaeoniaApp

/// The phase the server's state and the moves saved on the phone put the person in.
struct GuessMySpotResolverTests {
    let me = UUID()
    let partner = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let bergen = GuessMySpotCoordinate(latitude: 60.3913, longitude: 5.3221)
    let oslo = GuessMySpotCoordinate(latitude: 59.9139, longitude: 10.7522)

    // MARK: Fixtures

    func game(turn: UUID, rounds: Int = 1) -> RemoteGuessMySpotGame {
        RemoteGuessMySpotGame(
            id: UUID(),
            turnUserID: turn,
            turnStartedAt: now,
            sharedPoints: 0,
            myPoints: 0,
            partnerPoints: 0,
            roundCount: rounds,
            version: 1,
            createdByUserID: me,
            createdAt: now,
            updatedAt: now
        )
    }

    func round(
        _ number: Int = 1,
        sender: UUID,
        spot: GuessMySpotCoordinate? = nil,
        guess: GuessMySpotCoordinate? = nil,
        seen: Bool = false
    ) -> RemoteGuessMySpotRound {
        var round = RemoteGuessMySpotRound(
            id: UUID(),
            roundNumber: number,
            senderUserID: sender,
            guesserUserID: sender == me ? partner : me,
            photoMediaAssetID: UUID(),
            photoWidth: 4,
            photoHeight: 3,
            spotLatitude: spot?.latitude,
            spotLongitude: spot?.longitude,
            sentAt: now,
            guessedAt: guess == nil ? nil : now,
            myRevealSeenAt: seen ? now : nil
        )
        round.guess = guess
        return round
    }

    func state(
        game: RemoteGuessMySpotGame?,
        current: RemoteGuessMySpotRound? = nil,
        previous: RemoteGuessMySpotRound? = nil
    ) -> RemoteGuessMySpotState {
        RemoteGuessMySpotState(
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
        _ state: RemoteGuessMySpotState?,
        pending: GuessMySpotPendingWork = .none,
        hasLoaded: Bool = true,
        deferred: Set<UUID> = []
    ) -> GuessMySpotResolution {
        GuessMySpotResolver(userID: me).resolve(
            state: state,
            hasLoaded: hasLoaded,
            isStarting: false,
            pending: pending,
            deferredReveals: deferred
        )
    }

    func send(_ round: Int) -> GuessMySpotSendPayload {
        GuessMySpotSendPayload(
            details: GuessMySpotSendDetails(
                roundID: UUID(), roundNumber: round, spot: bergen, placeName: "Bergen", takenOn: nil
            ),
            coupleID: UUID(),
            width: 4,
            height: 3,
            reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
            finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2),
            createdAt: now
        )
    }

    // MARK: Before the game

    @Test func nothingReadIsLoadingAndNoGameIsStarting() {
        #expect(resolve(nil, hasLoaded: false).phase == .loading)
        #expect(resolve(nil).phase == .starting)
        #expect(resolve(state(game: nil)).phase == .starting)
    }

    @Test func aNewGameIsTheFirstSendersTurn() {
        #expect(resolve(state(game: game(turn: me, rounds: 0))).phase == .send)
        #expect(resolve(state(game: game(turn: partner, rounds: 0))).phase == .waitingForPhoto)
    }

    // MARK: Turns

    @Test func thePartnersPhotoWaitsForMyGuess() {
        let open = round(sender: partner)
        let resolution = resolve(state(game: game(turn: me), current: open))
        #expect(resolution.phase == .guess)
        #expect(resolution.round?.id == open.id)
        #expect(resolution.isYourTurn)
    }

    @Test func myPhotoWaitsForTheGuess() {
        let resolution = resolve(state(game: game(turn: partner), current: round(sender: me, spot: bergen)))
        #expect(resolution.phase == .waitingForGuess(isQueued: false))
        #expect(!resolution.isYourTurn)
    }

    @Test func aSeenGuessedRoundHandsTheNextSendToItsGuesser() {
        let mine = round(sender: partner, spot: bergen, guess: oslo, seen: true)
        #expect(resolve(state(game: game(turn: me), current: mine)).phase == .send)
        let theirs = round(sender: me, spot: bergen, guess: oslo, seen: true)
        #expect(resolve(state(game: game(turn: partner), current: theirs)).phase == .waitingForPhoto)
    }

    // MARK: Reveals

    @Test func anUnseenGuessedRoundIsTheReveal() {
        let guessed = round(sender: me, spot: bergen, guess: oslo)
        let resolution = resolve(state(game: game(turn: partner), current: guessed))
        #expect(resolution.phase == .reveal(isHeld: false))
        let distance = GuessMySpotRules.distanceMeters(oslo, bergen)
        #expect(resolution.round?.knownDistance == distance)
        #expect(resolution.round?.knownPoints == GuessMySpotRules.points(distanceMeters: distance))
    }

    @Test func aMissedRevealComesBeforeThePartnersNextPhoto() {
        let guessed = round(1, sender: me, spot: bergen, guess: oslo)
        let next = round(2, sender: partner)
        let resolution = resolve(state(game: game(turn: me, rounds: 2), current: next, previous: guessed))
        #expect(resolution.phase == .reveal(isHeld: false))
        #expect(resolution.round?.id == guessed.id)
    }

    @Test func aRevealMarkedSeenOnThePhoneMovesOn() {
        let guessed = round(sender: me, spot: bergen, guess: oslo)
        var pending = GuessMySpotPendingWork.none
        pending.seenReveals = [guessed.id]
        #expect(resolve(state(game: game(turn: partner), current: guessed), pending: pending).phase == .waitingForPhoto)
    }

    @Test func aGuessOnThePhoneHoldsTheRevealUntilTheSpotIsHere() {
        let open = round(sender: partner)
        var pending = GuessMySpotPendingWork.none
        pending.guesses[open.id] = oslo
        let resolution = resolve(state(game: game(turn: me), current: open), pending: pending)
        #expect(resolution.phase == .reveal(isHeld: true))
        #expect(resolution.round?.guess == oslo)
        #expect(resolution.round?.knownDistance == nil)
    }

    @Test func aHeldRevealSteppedPastGoesOnToSending() {
        let open = round(sender: partner)
        var pending = GuessMySpotPendingWork.none
        pending.guesses[open.id] = oslo
        let state = state(game: game(turn: me), current: open)
        #expect(resolve(state, pending: pending, deferred: [open.id]).phase == .send)
    }

    // MARK: Sends on the phone

    @Test func aSendOnThePhoneWaitsForTheGuessAsQueued() {
        var pending = GuessMySpotPendingWork.none
        let queued = send(1)
        pending.sends = [queued]
        let resolution = resolve(state(game: game(turn: me, rounds: 0)), pending: pending)
        #expect(resolution.phase == .waitingForGuess(isQueued: true))
        #expect(resolution.round?.spot == bergen)
        #expect(resolution.round?.placeName == "Bergen")
        // The photo of a send not on the server yet is named by its round.
        #expect(resolution.round?.photoMediaAssetID == queued.roundID)
    }

    @Test func aSendAfterAQueuedGuessFollowsTheHeldRevealOnceSteppedPast() {
        let open = round(1, sender: partner)
        var pending = GuessMySpotPendingWork.none
        pending.guesses[open.id] = oslo
        pending.sends = [send(2)]
        let state = state(game: game(turn: me), current: open)
        #expect(resolve(state, pending: pending).phase == .reveal(isHeld: true))
        #expect(resolve(state, pending: pending, deferred: [open.id]).phase == .waitingForGuess(isQueued: true))
    }

    @Test func aSendThatCanNotFollowTheServersRoundIsIgnored() {
        var pending = GuessMySpotPendingWork.none
        pending.sends = [send(2)]
        let open = round(1, sender: partner)
        #expect(resolve(state(game: game(turn: me), current: open), pending: pending).phase == .guess)
    }

    @Test func aSendLeftFromATurnThatMovedOnShowsNowhere() {
        let seen = round(4, sender: partner, spot: bergen, guess: oslo, seen: true)
        var pending = GuessMySpotPendingWork.none
        pending.sends = [send(2)]
        #expect(resolve(state(game: game(turn: me, rounds: 4), current: seen), pending: pending).phase == .send)
        pending.sends = [send(5)]
        #expect(resolve(state(game: game(turn: me, rounds: 4), current: seen), pending: pending).phase
            == .waitingForGuess(isQueued: true))
    }
}

// MARK: - Attention

extension GuessMySpotResolverTests {
    /// The partner's photo makes it my turn, named by the round, also while my last
    /// round's reveal waits. My own guess ends it, and my own photo is never my turn.
    @Test func thePartnersPhotoMakesItMyTurnUntilIGuess() {
        func turn(_ state: RemoteGuessMySpotState, pending: GuessMySpotPendingWork = .none) -> String? {
            GuessMySpotResolver(userID: me).attention(state: state, pending: pending).turn
        }
        let revealed = round(1, sender: me, spot: bergen, guess: oslo)
        var seen = revealed
        seen.myRevealSeenAt = now
        let theirs = round(2, sender: partner)
        var myGuess = GuessMySpotPendingWork.none
        myGuess.guesses[theirs.id] = oslo

        let handedOver = turn(state(game: game(turn: me), current: theirs, previous: revealed))
        #expect(handedOver != nil)
        #expect(turn(state(game: game(turn: me), current: theirs, previous: seen)) == handedOver)
        #expect(turn(state(game: game(turn: me), current: theirs), pending: myGuess) == nil)
        #expect(turn(state(game: game(turn: partner), current: round(sender: me))) == nil)
    }
}
