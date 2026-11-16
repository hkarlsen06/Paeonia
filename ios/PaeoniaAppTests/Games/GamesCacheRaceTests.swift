import Foundation
import Testing
@testable import PaeoniaApp

/// A one-shot read of the games state must not undo a write the live feed made in the meantime.
@MainActor
struct GamesCacheRaceTests {
    private let environment = GamesTestEnvironment(state: nil)

    @Test func anOlderOneShotReadNeverOverwritesALiveWrite() async {
        let cache = InMemoryGamesCache()
        let older = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me)
        )
        let newer = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil)
        )

        let ticket = await cache.beginFetch()
        // The live feed writes while the one-shot read is on its way.
        await cache.saveState(newer, ownerUserID: GameFixture.me)
        let saved = await cache.saveFetchedState(older, ownerUserID: GameFixture.me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == newer)
    }

    @Test func aDrawingTakenBackIsNewerThanTheSentStateBecauseTheGameVersionWentUp() async {
        let cache = InMemoryGamesCache()
        let sent = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner, version: 9),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true)
        )
        let keptDrawing = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me, version: 10),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        await cache.saveState(sent, ownerUserID: GameFixture.me)

        let ticket = await cache.beginFetch()
        let saved = await cache.saveFetchedState(keptDrawing, ownerUserID: GameFixture.me, ticket: ticket)

        #expect(saved)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == keptDrawing)
        #expect(sent.isOlder(than: keptDrawing))
    }

    @Test func aOneShotReadWithNoLiveWriteInBetweenIsSaved() async throws {
        let cache = InMemoryGamesCache()
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me)
        )
        environment.gateway.setStateToLoad(state)

        let matched = try await cache.fetchState(from: environment.gateway, ownerUserID: GameFixture.me)

        #expect(matched)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == state)
        let otherPerson = try await cache.fetchState(from: environment.gateway, ownerUserID: UUID())
        #expect(!otherPerson)
    }
}
