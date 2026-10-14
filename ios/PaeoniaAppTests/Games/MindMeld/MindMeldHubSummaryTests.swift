import Foundation
import Testing
@testable import PaeoniaApp

/// What the hub card says for each state of the game, and when it counts as the
/// person's turn.
struct MindMeldHubSummaryTests: MindMeldResolverFixtures {
    let me = UUID()
    let partner = UUID()

    private func summary(_ game: RemoteMindMeldGame?) -> MindMeldHubSummary {
        let read = state(current: game)
        return MindMeldHubSummary(state: read, resolution: resolve(read))
    }

    @Test func noGameYetOffersToPlay() {
        let result = summary(nil)

        #expect(result.status == .new)
        #expect(!result.isYourTurn)
    }

    @Test func anOpenRoundNobodyLockedInIsNobodysTurn() {
        let result = summary(game(rounds: [open(1)]))

        #expect(result.status == .open(round: 1))
        #expect(!result.isYourTurn)
    }

    @Test func aRoundLaterThanTheFirstNamesItsNumber() {
        let result = summary(game(rounds: [revealed(1), open(2)]))

        #expect(result.status == .open(round: 2))
    }

    @Test func thePartnersLockInIsMyTurn() {
        let result = summary(game(rounds: [open(1, partnerLocked: true)]))

        #expect(result.status == .partnerLocked)
        #expect(result.isYourTurn)
    }

    @Test func myLockInMeansWaitingAndNotMyTurn() {
        let result = summary(game(rounds: [open(1, mine: "ocean")]))

        #expect(result.status == .waiting)
        #expect(!result.isYourTurn)
    }

    @Test func anUnseenRevealIsMyTurn() {
        let result = summary(game(rounds: [revealed(1, seen: false), open(2)]))

        #expect(result.status == .reveal)
        #expect(result.isYourTurn)
    }

    @Test func aSeenMeldShowsTheRoundsItTook() {
        let rounds = [revealed(1), revealed(2), revealed(3, "fish", "fish", outcome: .match)]
        let result = summary(game(.melded, rounds: rounds, endSeen: true))

        #expect(result.status == .melded(rounds: 3))
        #expect(!result.isYourTurn)
    }

    @Test func aSeenGameThatRanOutOfRoundsGotAway() {
        let rounds = (1...10).map { revealed($0) }
        let result = summary(game(.ended, rounds: rounds, reason: .rounds, endSeen: true))

        #expect(result.status == .gotAway)
        #expect(!result.isYourTurn)
    }

    @Test func theCouplesNumbersComeFromTheStats() {
        let stats = RemoteMindMeldStats(melds: 3, fewestRounds: 2, games: 5)
        let fresh = RemoteMindMeldState(
            userID: me, partnerUserID: partner, coupleID: UUID(), current: nil, previous: nil, stats: stats
        )
        let result = MindMeldHubSummary(state: fresh, resolution: resolve(fresh))

        #expect(result.melds == 3)
        #expect(result.hasFinishedGames)
    }

    @Test func aCoupleWithoutFinishedGamesHasNoMeldsLink() {
        let stats = RemoteMindMeldStats(melds: 0, fewestRounds: nil, games: 0)
        let fresh = RemoteMindMeldState(
            userID: me, partnerUserID: partner, coupleID: UUID(), current: nil, previous: nil, stats: stats
        )
        let result = MindMeldHubSummary(state: fresh, resolution: resolve(fresh))

        #expect(!result.hasFinishedGames)
    }
}
