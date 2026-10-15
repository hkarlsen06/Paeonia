import Foundation
import Testing
@testable import PaeoniaApp

/// The file store behind the games caches: one read per person, writes only
/// for real changes, and a purge that drops the copy in memory too.
@MainActor
struct GamesDocumentStoreTests {
    private let owner = UUID()
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func makeStore() -> GamesDocumentStore<StoryChainLocalDocument> {
        GamesDocumentStore(directoryURL: directory, schemaVersion: 1)
    }

    private var file: URL {
        directory.appendingPathComponent(owner.uuidString.lowercased() + ".json")
    }

    @Test func aDocumentIsReadFromItsFileOnce() {
        defer { try? FileManager.default.removeItem(at: directory) }
        var first = makeStore()
        first.update(ownerUserID: owner) { $0.draft = "hello" }

        var next = makeStore()
        #expect(next.document(ownerUserID: owner).draft == "hello")

        // The copy in memory answers, so a file that changed underneath is not read again.
        try? FileManager.default.removeItem(at: file)
        #expect(next.document(ownerUserID: owner).draft == "hello")
    }

    @Test func aChangeThatChangesNothingWritesNothing() {
        defer { try? FileManager.default.removeItem(at: directory) }
        var store = makeStore()
        store.update(ownerUserID: owner) { $0.draft = "hello" }
        try? FileManager.default.removeItem(at: file)

        store.update(ownerUserID: owner) { $0.draft = "hello" }
        #expect(!FileManager.default.fileExists(atPath: file.path))

        store.update(ownerUserID: owner) { $0.draft = "bye" }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func updateReturnsWhatTheChangeReturns() {
        defer { try? FileManager.default.removeItem(at: directory) }
        var store = makeStore()

        let rescued = store.update(ownerUserID: owner) { document -> String? in
            document.rescuedLines = ["one", "two"]
            return document.takeRescuedLines(into: "")
        }

        #expect(rescued == "one two")
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
