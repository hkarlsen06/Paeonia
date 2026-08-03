import Foundation
import SwiftData
import Testing
@testable import PaeoniaApp

struct LocalStoreTests {
    @Test func createsPersistentStoreDirectoryBeforeOpeningStore() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = rootDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try PaeoniaLocalStore.createStoreDirectory(for: storeURL)

        var isDirectory: ObjCBool = false
        let directoryExists = FileManager.default.fileExists(
            atPath: storeURL.deletingLastPathComponent().path,
            isDirectory: &isDirectory
        )
        #expect(directoryExists)
        #expect(isDirectory.boolValue)
    }

    @Test func inMemoryStorePersistsSyncModels() throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let context = ModelContext(store.container)
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operationID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let clientID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let syncState = LocalSyncState(
            ownerUserID: ownerUserID,
            scopeKind: .user,
            streamKey: .profile
        )
        let operation = SyncClientOperation(
            id: operationID,
            clientID: clientID,
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let pendingOperation = LocalPendingSyncOperation(
            ownerUserID: ownerUserID,
            operation: operation,
            operationKind: .createPendingMediaUpload,
            idempotencyScope: "profile-photo:\(operationID.uuidString)"
        )

        context.insert(syncState)
        context.insert(pendingOperation)
        try context.save()

        let syncStates = try context.fetch(FetchDescriptor<LocalSyncState>())
        let pendingOperations = try context.fetch(FetchDescriptor<LocalPendingSyncOperation>())

        #expect(syncStates.map(\.key) == [syncState.key])
        #expect(pendingOperations.map(\.clientOperationID) == [operationID])
    }
}
