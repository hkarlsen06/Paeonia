import Foundation
import SwiftData

nonisolated final class PaeoniaLocalStore: Sendable {
    /// One production container shared by every repository and feature service.
    /// Opening the same SwiftData store repeatedly is expensive enough to stall a
    /// cold-launch animation, and separate containers also make local writes harder
    /// to observe consistently across features. Tests can still create isolated
    /// in-memory instances through `init(inMemory:)`.
    /// The app cannot keep anything without it, so a store that will not open stops
    /// the app instead of losing what the person saves.
    static let shared: PaeoniaLocalStore = {
        do {
            return try PaeoniaLocalStore()
        } catch {
            fatalError("Could not open the local store: \(error)")
        }
    }()

    let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema([
            LocalSyncState.self,
            LocalPendingSyncOperation.self,
            LocalAccessSyncSnapshot.self,
            LocalRelationshipSyncEvent.self,
            LocalLocationVisibilitySnapshot.self,
            LocalOwnLocationSnapshot.self,
            LocalMemoryRecord.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        if !inMemory {
            try Self.createStoreDirectory(for: configuration.url)
        }

        self.container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func createStoreDirectory(for storeURL: URL) throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
