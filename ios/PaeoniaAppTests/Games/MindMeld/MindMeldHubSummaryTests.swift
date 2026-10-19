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
}
