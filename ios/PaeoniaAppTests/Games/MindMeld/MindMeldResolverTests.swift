import Foundation
import Testing
@testable import PaeoniaApp

/// The phase a state puts the person in, from the server's rows and the moves
/// saved on the phone: nothing to show yet, writing and waiting, and reveals.
struct MindMeldResolverTests: MindMeldResolverFixtures {
    let me = UUID()
    let partner = UUID()

    // MARK: Nothing to show yet

    @Test func noStateIsLoadingUntilTheFirstReadFinishes() {
        #expect(resolve(nil, hasLoaded: false).phase == .loading)
        #expect(resolve(nil, hasLoaded: true).phase == .starting)
    }

    @Test func noGameAtAllIsStarting() {
        let resolution = resolve(state(current: nil))

        #expect(resolution.phase == .starting)
        #expect(resolution.game == nil && resolution.round == nil)
    }

    @Test func aGameBeingStartedIsStartingWhateverTheStateHolds() {
        let finished = game(.melded, rounds: [revealed(1, "fish", "fish", outcome: .match)])
        var pending = MindMeldPendingWork.none
        pending.isStarting = true

        #expect(resolve(finished, pending: pending).phase == .starting)
        #expect(resolve(nil, pending: pending, hasLoaded: false).phase == .loading)
    }

    @Test func aFinishedGameThatARestartEndedHasNothingToShowSoTheNextOneStarts() {
        let restarted = game(.ended, rounds: [open(1)], reason: .restart, endedBy: partner, endSeen: true)

        #expect(resolve(restarted).phase == .starting)
    }

    @Test func aGameInPlayWithoutAnOpenRoundWaitsForTheNextState() {
        #expect(resolve(game(rounds: [revealed(1, seen: false)])).phase == .reveal)
        #expect(resolve(game(rounds: [revealed(1, seen: true)])).phase == .loading)
    }

    // MARK: Write and waiting

    @Test func anOpenRoundNobodyLockedInNeedsMyWord() {
        let resolution = resolve(game(rounds: [open(1)]))

        #expect(resolution.phase == .write)
        #expect(resolution.roundNumber == 1)
        #expect(resolution.connectingPair == nil)
        #expect(resolution.trail.isEmpty)
        #expect(!resolution.isYourTurn)
    }

    @Test func myWordOnTheServerMeansWaitingForThePartner() {
        let resolution = resolve(game(rounds: [open(1, mine: "ocean")]))

        #expect(resolution.phase == .waiting(isQueued: false))
        #expect(resolution.round?.myWord == "ocean")
        #expect(!resolution.isYourTurn)
    }

    @Test func aLockInMadeOfflineShowsAsWaitingAndQueued() {
        let round = open(1)
        var pending = MindMeldPendingWork.none
        pending.lockedWords[round.id] = "ocean"
        let resolution = resolve(game(rounds: [round]), pending: pending)

        #expect(resolution.phase == .waiting(isQueued: true))
        #expect(resolution.round?.myWord == "ocean")
        #expect(resolution.game?.openRound?.myWord == "ocean")
    }

    @Test func aQueuedLockInThatTheServerAlreadyHasIsNotQueued() {
        let round = open(1, mine: "ocean")
        var pending = MindMeldPendingWork.none
        pending.lockedWords[round.id] = "ocean"

        #expect(resolve(game(rounds: [round]), pending: pending).phase == .waiting(isQueued: false))
    }

    @Test func aQueuedLockInDoesNotChangeAGameTheServerCalledFinished() {
        let first = revealed(1, "fish", "fish", outcome: .match)
        var pending = MindMeldPendingWork.none
        pending.lockedWords[first.id] = "other"
        let resolution = resolve(game(.melded, rounds: [first]), pending: pending)

        #expect(resolution.round?.myWord == "fish")
    }

    @Test func thePartnerLockingInFirstLeavesMeOnTheWritePhaseWithTheirStatus() {
        let resolution = resolve(game(rounds: [open(1, partnerLocked: true)]))

        #expect(resolution.phase == .write)
        #expect(resolution.round?.partnerLocked == true)
        #expect(resolution.isYourTurn)
    }

    @Test func aQueuedLockInWithThePartnerAlreadyLockedStaysWaitingUntilTheServerReveals() {
        let round = open(1, partnerLocked: true)
        var pending = MindMeldPendingWork.none
        pending.lockedWords[round.id] = "ocean"
        let resolution = resolve(game(rounds: [round]), pending: pending)

        #expect(resolution.phase == .waiting(isQueued: true))
        #expect(!resolution.isYourTurn)
    }

    // MARK: Reveals

    @Test func aRevealIAmYetToSeeComesBeforeTheNextRoundsWritePhase() {
        let first = revealed(1, "ocean", "sushi", seen: false)
        let second = open(2)
        let resolution = resolve(game(rounds: [first, second]))

        #expect(resolution.phase == .reveal)
        #expect(resolution.round?.id == first.id)
        #expect(resolution.displayOutcome == .miss)
        #expect(resolution.isYourTurn)
        #expect(resolution.roundNumber == 1)
    }

    @Test func aSeenMarkWaitingOnThePhoneMovesOnToTheNextRound() {
        let first = revealed(1, seen: false)
        let second = open(2)
        var pending = MindMeldPendingWork.none
        pending.seenReveals.insert(first.id)
        let resolution = resolve(game(rounds: [first, second]), pending: pending)

        #expect(resolution.phase == .write)
        #expect(resolution.round?.id == second.id)
        #expect(resolution.roundNumber == 2)
        #expect(resolution.connectingPair?.mine == "ocean")
        #expect(resolution.connectingPair?.theirs == "sushi")
    }

    @Test func aRevealTheServerKnowsIHaveSeenMovesOnToTheNextRound() {
        #expect(resolve(game(rounds: [revealed(1, seen: true), open(2)])).phase == .write)
    }

    @Test func onlyTheLatestRevealedRoundCanBeAnUnseenReveal() {
        // The person never saw round 1 on this phone, but moved past round 2.
        let rounds = [revealed(1, seen: false), revealed(2, "salt", "fish", seen: true), open(3)]

        #expect(resolve(game(rounds: rounds)).phase == .write)
    }

    @Test func iCanLockInTheNextRoundBeforeSeeingTheLastRevealAndTheRevealStillComesFirst() {
        let first = revealed(1, seen: false)
        let second = open(2, mine: "salt")
        let resolution = resolve(game(rounds: [first, second]))

        #expect(resolution.phase == .reveal)
        #expect(resolution.round?.id == first.id)
    }

    @Test func afterTheRevealTheNextRoundCanBeWaitingWithTheWordIAlreadyLocked() {
        let first = revealed(1, seen: true)
        let second = open(2, mine: "salt", partnerLocked: false)

        #expect(resolve(game(rounds: [first, second])).phase == .waiting(isQueued: false))
    }
}
