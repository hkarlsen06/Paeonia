import SwiftData

protocol LocalStore: Sendable {
    nonisolated var container: ModelContainer { get }
}

final class PaeoniaLocalStore: LocalStore, @unchecked Sendable {
    nonisolated let container: ModelContainer

    nonisolated init(inMemory: Bool = false) throws {
        let schema = Schema([
            LocalSyncState.self,
            LocalPendingSyncOperation.self,
            LocalAccessSyncSnapshot.self,
            LocalRelationshipSyncEvent.self,
            LocalLocationVisibilitySnapshot.self,
            LocalOwnLocationSnapshot.self
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
