import Foundation
import Testing
@testable import PaeoniaApp

/// The resolver's handling of near misses, endings and an earlier game.
struct MindMeldResolverEndingTests: MindMeldResolverFixtures {
    let me = UUID()
    let partner = UUID()

    // MARK: Near misses and Count it

    @Test func aQueuedCountTurnsTheNearMissIntoAMeldInPlace() {
        let near = revealed(1, "dog", "dogs", outcome: .near, seen: false)
        let next = open(2)
        let uncounted = resolve(game(rounds: [near, next]))

        #expect(uncounted.phase == .reveal)
        #expect(uncounted.displayOutcome == .near)
        #expect(uncounted.canCount)
        #expect(uncounted.game?.state == .playing)

        var pending = MindMeldPendingWork.none
        pending.countedRounds.insert(near.id)
        let counted = resolve(game(rounds: [near, next]), pending: pending)

        #expect(counted.phase == .reveal)
        #expect(counted.round?.id == near.id)
        #expect(counted.round?.countedByUserID == me)
        #expect(counted.displayOutcome == .meld)
        #expect(counted.game?.state == .melded)
        // The round that was open after it is gone.
        #expect(counted.game?.rounds.map(\.id) == [near.id])
        #expect(!counted.canCount)
    }

    @Test func aPartnersCountAfterISawTheNearMissShowsTheMeldAsAnEndingToSee() {
        let near = revealed(1, "dog", "dogs", outcome: .near, seen: true, countedBy: partner)
        let resolution = resolve(game(.melded, rounds: [near]))

        #expect(resolution.phase == .reveal)
        #expect(resolution.round?.id == near.id)
        #expect(resolution.displayOutcome == .meld)
    }

    @Test func aNearMissIsNotACountableOnceItWasCountedOrTheGameWasRestarted() {
        let near = revealed(1, "dog", "dogs", outcome: .near, countedBy: partner)
        let restarted = game(.ended, rounds: [revealed(1, outcome: .near), open(2)], reason: .restart, endedBy: partner)

        #expect(resolve(game(.melded, rounds: [near])).canCount == false)
        #expect(restarted.countableRound == nil)
    }

    @Test func aNearMissInTheLastRoundStaysNearAndCanStillBeCounted() {
        let rounds = (1...9).map { revealed($0) } + [revealed(10, "dog", "dogs", outcome: .near)]
        let ended = game(.ended, rounds: rounds, reason: .rounds, endSeen: true)
        let resolution = resolve(ended)

        #expect(resolution.phase == .over)
        #expect(resolution.displayOutcome == .near)
        #expect(resolution.canCount)

        var pending = MindMeldPendingWork.none
        pending.countedRounds.insert(rounds[9].id)
        let counted = resolve(ended, pending: pending)

        #expect(counted.game?.state == .melded && counted.game?.endReason == nil)
        #expect(counted.displayOutcome == .meld)
        #expect(counted.phase == .over)
    }

    // MARK: Endings

    @Test func aFinishedGameWhoseEndingIHaveNotSeenIsAReveal() {
        let meld = revealed(2, "fish", "fish", outcome: .match, seen: true)
        let resolution = resolve(game(.melded, rounds: [revealed(1), meld]))

        #expect(resolution.phase == .reveal)
        #expect(resolution.round?.id == meld.id)
        #expect(resolution.displayOutcome == .meld)
        #expect(resolution.isYourTurn)
    }

    @Test func aFinishedGameWhoseEndingIHaveSeenIsOverAndShowsItsLastRound() {
        let meld = revealed(2, "fish", "fish", outcome: .match)
        let finished = game(.melded, rounds: [revealed(1), meld], endSeen: true)
        let resolution = resolve(finished)

        #expect(resolution.phase == .over)
        #expect(resolution.round?.id == meld.id)
        #expect(resolution.trail.map(\.roundNumber) == [1, 2])
        #expect(!resolution.isYourTurn)
    }

    @Test func aSeenMarkForTheEndingWaitingOnThePhoneMakesItOver() {
        let finished = game(.melded, rounds: [revealed(1, "fish", "fish", outcome: .match)])
        var pending = MindMeldPendingWork.none
        pending.seenEnds.insert(finished.id)

        #expect(resolve(finished).phase == .reveal)
        #expect(resolve(finished, pending: pending).phase == .over)
    }

    @Test func missingTheLastRoundOfTenIsGotAwayAndNotAnyEarlierMiss() {
        let rounds = (1...10).map { revealed($0) }
        let ended = game(.ended, rounds: rounds, reason: .rounds)
        let resolution = resolve(ended)

        #expect(resolution.phase == .reveal)
        #expect(resolution.displayOutcome == .gotAway)
        let expected = [MindMeldRevealOutcome](repeating: .miss, count: 9) + [.gotAway]
        #expect(resolution.trail.map(\.outcome) == expected)
    }

    // MARK: An earlier game

    @Test func aPreviousGameWhoseEndingIHaveNotSeenComesBeforeTheNewGame() {
        let meld = revealed(2, "fish", "fish", outcome: .match, seen: true)
        let previous = game(.melded, number: 1, rounds: [revealed(1), meld])
        let current = game(number: 2, rounds: [open(1)])
        let resolution = resolve(state(current: current, previous: previous))

        #expect(resolution.phase == .reveal)
        #expect(resolution.game?.id == previous.id)
        #expect(resolution.round?.id == meld.id)
        #expect(!resolution.partnerRestartedNote)
    }

    @Test func onceThatEndingIsSeenThePlayContinuesInTheNewGame() {
        let previous = game(.melded, number: 1, rounds: [revealed(1, "fish", "fish", outcome: .match)])
        let current = game(number: 2, rounds: [open(1)])
        var pending = MindMeldPendingWork.none
        pending.seenEnds.insert(previous.id)
        let resolution = resolve(state(current: current, previous: previous), pending: pending)

        #expect(resolution.phase == .write)
        #expect(resolution.game?.id == current.id)
    }

    @Test func aPreviousEndingTheServerMarkedSeenIsSkipped() {
        let previous = game(.melded, number: 1, rounds: [revealed(1, "fish", "fish", outcome: .match)], endSeen: true)
        let current = game(number: 2, rounds: [open(1)])

        #expect(resolve(state(current: current, previous: previous)).phase == .write)
    }

    @Test func aPartnersRestartShowsTheNewGameWithAOneTimeNote() {
        let previous = game(.ended, number: 1, rounds: [revealed(1), open(2)], reason: .restart, endedBy: partner)
        let current = game(number: 2, rounds: [open(1)])
        let resolution = resolve(state(current: current, previous: previous))

        #expect(resolution.phase == .write)
        #expect(resolution.game?.id == current.id)
        #expect(resolution.partnerRestartedNote)
        #expect(resolution.partnerRestartedGameID == previous.id)

        var pending = MindMeldPendingWork.none
        pending.seenEnds.insert(previous.id)
        let afterMark = resolve(state(current: current, previous: previous), pending: pending)

        #expect(afterMark.phase == .write)
        #expect(!afterMark.partnerRestartedNote)
    }

    @Test func myOwnRestartGoesStraightToTheNewGameWithoutANote() {
        let current = game(number: 2, rounds: [open(1)])
        let rounds = [revealed(1), open(2)]
        let markedSeen = game(.ended, number: 1, rounds: rounds, reason: .restart, endedBy: me, endSeen: true)
        let notMarked = game(.ended, number: 1, rounds: rounds, reason: .restart, endedBy: me)

        for previous in [markedSeen, notMarked] {
            let resolution = resolve(state(current: current, previous: previous))
            #expect(resolution.phase == .write)
            #expect(resolution.game?.id == current.id)
            #expect(!resolution.partnerRestartedNote)
        }
    }

    @Test func aRestartedGameWithRevealedRoundsNeverReplaysItsLastRound() {
        let rounds = [revealed(1, seen: false), open(2)]
        let previous = game(.ended, number: 1, rounds: rounds, reason: .restart, endedBy: partner)
        let current = game(number: 2, rounds: [open(1)])

        #expect(resolve(state(current: current, previous: previous)).phase == .write)
    }
}
