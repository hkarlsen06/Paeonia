import Foundation
import Testing
@testable import PaeoniaApp

/// The file store behind the games caches: a purge drops the copy in memory too.
@MainActor
struct GamesDocumentStoreTests {
    private let owner = UUID()
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func makeStore() -> GamesDocumentStore<StoryChainLocalDocument> {
        GamesDocumentStore(directoryURL: directory, schemaVersion: 1)
    }

    @Test func reopeningKeepsGameContentAndInvitesWithoutLivePresence() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileGamesCache(directoryURL: directory)
        var state = GameFixture.state(
            settings: GameFixture.settings(), game: GameFixture.game(state: .drawing, turn: GameFixture.me)
        )
        state.myPresent = true
        state.partnerPresent = true
        var overview = RemoteGamesOverview(drawAndGuess: state)
        let invitedAt = Date(timeIntervalSince1970: 100)
        overview.presence = [RemoteGamePresence(
            kind: .drawAndGuess, myPresent: true, partnerPresent: true, lastInviteAt: invitedAt
        )]
        await cache.saveOverview(overview, ownerUserID: GameFixture.me)
        await cache.saveState(state, ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).state?.partnerPresent == true)
        let reopened = FileGamesCache(directoryURL: directory)
        let document = await reopened.document(ownerUserID: GameFixture.me)
        #expect(document.state?.partnerPresent == false)
        #expect(document.overview?.presence(for: .drawAndGuess)?.partnerPresent == false)
        #expect(document.state?.settings == state.settings)
        #expect(document.state?.game == state.game)
        #expect(document.overview?.presence(for: .drawAndGuess)?.lastInviteAt == invitedAt)
        #expect(document.state?.lastInviteAt == state.lastInviteAt)
        await cache.clearPresence(ownerUserID: GameFixture.me, overview: false)
        let stillLive = await cache.document(ownerUserID: GameFixture.me)
        #expect(stillLive.overview?.presence(for: .drawAndGuess)?.partnerPresent == true)
        await cache.clearPresence(ownerUserID: GameFixture.me, overview: true)
        let stopped = await cache.document(ownerUserID: GameFixture.me)
        #expect(stopped.overview?.presence(for: .drawAndGuess)?.partnerPresent == false)
    }

    @Test func clearingDropsTheCopyInMemoryAndTheFiles() {
        defer { try? FileManager.default.removeItem(at: directory) }
        var store = makeStore()
        store.update(ownerUserID: owner) { $0.draft = "hello" }

        store.clear()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(store.document(ownerUserID: owner) == StoryChainLocalDocument())
    }

    @Test func aFileFromAnotherSchemaVersionReadsAsEmpty() {
        defer { try? FileManager.default.removeItem(at: directory) }
        var old = GamesDocumentStore<StoryChainLocalDocument>(directoryURL: directory, schemaVersion: 1)
        old.update(ownerUserID: owner) { $0.draft = "hello" }

        var newer = GamesDocumentStore<StoryChainLocalDocument>(directoryURL: directory, schemaVersion: 2)
        #expect(newer.document(ownerUserID: owner) == StoryChainLocalDocument())
    }

    @Test func aPurgeAlsoDropsTheCopyTheFileCacheKeepsInMemory() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileGamesCache(directoryURL: directory)
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)
        await cache.saveState(state, ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == state)

        await cache.clearAll()

        #expect(await cache.document(ownerUserID: GameFixture.me).state == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
