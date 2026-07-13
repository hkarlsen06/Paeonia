import SwiftData

protocol LocalStore: Sendable {
    nonisolated var container: ModelContainer { get }
}

final class PaeoniaLocalStore: LocalStore, @unchecked Sendable {
    /// One production container shared by every repository and feature service.
    /// Opening the same SwiftData store repeatedly is expensive enough to stall a
    /// cold-launch animation, and separate containers also make local writes harder
    /// to observe consistently across features. Tests can still create isolated
    /// in-memory instances through `init(inMemory:)`.
    nonisolated static let shared = try? PaeoniaLocalStore()

    nonisolated let container: ModelContainer

    nonisolated init(inMemory: Bool = false) throws {
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

        self.container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
