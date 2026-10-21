import Foundation
import Testing
@testable import PaeoniaApp

struct LiveSyncCoordinatorDemandTests {
    /// Counts runs and how many are running now.
    private final class CountingFeed: LiveFeed, @unchecked Sendable {
        let name: String
        let activation: LiveFeedActivation
        let runs = LockedBox<Int>(0)
        let running = LockedBox<Int>(0)

        init(name: String, activation: LiveFeedActivation) {
            self.name = name
            self.activation = activation
        }

        func run(session _: SyncSession, live _: LiveQueryService) async {
            runs.mutate { $0 += 1 }
            running.mutate { $0 += 1 }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            running.mutate { $0 -= 1 }
        }
    }

    private struct NeverTransport: LiveQueryTransport {
        func updates(path _: String, args _: [String: String]) -> AsyncThrowingStream<Data, any Error> {
            AsyncThrowingStream { _ in }
        }
    }

    private static let session = SyncSession(userID: UUID(), activeCoupleID: UUID())

    private static func makeCoordinator(
        feeds: [any LiveFeed],
        linger: Duration = .milliseconds(80)
    ) -> LiveSyncCoordinator {
        LiveSyncCoordinator(feeds: feeds, live: LiveQueryService(transport: NeverTransport()), lingerDelay: linger)
    }

    @Test func aFeedWithTopicsRunsOnlyWhileATopicIsHeld() async {
        let always = CountingFeed(name: "always", activation: .always)
        let games = CountingFeed(name: "games", activation: .whileNeeded([.gamesTab]))
        let coordinator = Self.makeCoordinator(feeds: [always, games])

        await coordinator.start(session: Self.session)
        #expect(await waitUntil { always.running.value == 1 })
        #expect(games.runs.value == 0)

        await coordinator.apply(.held([.gamesTab], sequence: 1))
        #expect(await waitUntil { games.running.value == 1 })

        await coordinator.apply(.held([.homeTab], sequence: 2))
        #expect(await waitUntil { games.running.value == 0 })
        #expect(always.running.value == 1)
        await coordinator.stop()
    }

    @Test func comingBackWithinTheLingerKeepsTheSameRun() async {
        let games = CountingFeed(name: "games", activation: .whileNeeded([.gamesTab]))
        let coordinator = Self.makeCoordinator(feeds: [games], linger: .milliseconds(300))
        await coordinator.start(session: Self.session)

        await coordinator.apply(.held([.gamesTab], sequence: 1))
        #expect(await waitUntil { games.running.value == 1 })
        await coordinator.apply(.held([.homeTab], sequence: 2))
        await coordinator.apply(.held([.gamesTab], sequence: 3))
        try? await Task.sleep(for: .milliseconds(500))

        #expect(games.runs.value == 1)
        #expect(games.running.value == 1)
        await coordinator.stop()
    }

    @Test func aTouchRunsTheFeedForTheLingerOnly() async {
        let games = CountingFeed(name: "games", activation: .whileNeeded([.gameTurns]))
        let coordinator = Self.makeCoordinator(feeds: [games])
        await coordinator.start(session: Self.session)

        await coordinator.apply(.touched([.gameTurns]))
        #expect(await waitUntil { games.running.value == 1 })
        #expect(await waitUntil { games.running.value == 0 })
        #expect(games.runs.value == 1)
        await coordinator.stop()
    }

    @Test func aTouchBeforeTheSessionStartsRunsWhenItStarts() async {
        let games = CountingFeed(name: "games", activation: .whileNeeded([.gameTurns]))
        let coordinator = Self.makeCoordinator(feeds: [games])

        await coordinator.apply(.touched([.gameTurns]))
        #expect(games.runs.value == 0)
        await coordinator.start(session: Self.session)

        #expect(await waitUntil { games.running.value == 1 })
        await coordinator.stop()
    }

    @Test func anOlderHeldEventDoesNotUndoANewerOne() async {
        let games = CountingFeed(name: "games", activation: .whileNeeded([.gamesTab]))
        let coordinator = Self.makeCoordinator(feeds: [games], linger: .milliseconds(10))
        await coordinator.start(session: Self.session)

        await coordinator.apply(.held([.gamesTab], sequence: 2))
        await coordinator.apply(.held([], sequence: 1))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(games.running.value == 1)
        await coordinator.stop()
    }

    @Test func stopEndsFeedsThatAreStillLingering() async {
        let games = CountingFeed(name: "games", activation: .whileNeeded([.gamesTab]))
        let coordinator = Self.makeCoordinator(feeds: [games], linger: .seconds(30))
        await coordinator.start(session: Self.session)
        await coordinator.apply(.held([.gamesTab], sequence: 1))
        #expect(await waitUntil { games.running.value == 1 })
        await coordinator.apply(.held([], sequence: 2))

        await coordinator.stop()

        #expect(games.running.value == 0)
    }
}
