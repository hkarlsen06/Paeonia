import Foundation

nonisolated protocol MemoryDataServicing: Actor {
    func loadCachedMemories(
        ownerUserID: UUID,
        includeHidden: Bool
    ) async throws -> [MemoryRecord]
    func loadCachedMemory(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord?
    func createMemory(
        ownerUserID: UUID,
        coupleID: UUID,
        memoryID: UUID,
        title: String,
        memoryDate: String,
        noteBody: String?,
        optimisticMedia: [MemoryMediaSnapshot],
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func updateMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        title: String,
        memoryDate: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func hideMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func upsertMemoryNote(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int?,
        body: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func attachMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        optimisticMedia: [MemoryMediaSnapshot],
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func removeMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        memoryMediaID: UUID,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func createMemoryThreadMessage(
        ownerUserID: UUID,
        memoryID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) async throws
}

nonisolated enum MemoryDataServiceError: Error, Equatable, Sendable {
    case missingMemory
    case missingCreateContent
    case emptyTitle
    case emptyNote
    case emptyThreadMessage
    case emptyMediaAttachment
}

actor MemoryDataService: MemoryDataServicing {
    let memoryStore: any MemoryRecordPersisting
    let pendingOperationStore: any PendingSyncOperationPersisting
    let encoder = JSONEncoder()

    init(
        memoryStore: any MemoryRecordPersisting,
        pendingOperationStore: any PendingSyncOperationPersisting
    ) {
        self.memoryStore = memoryStore
        self.pendingOperationStore = pendingOperationStore
    }

    func loadCachedMemories(
        ownerUserID: UUID,
        includeHidden: Bool = false
    ) async throws -> [MemoryRecord] {
        try await memoryStore.load(ownerUserID: ownerUserID, includeHidden: includeHidden)
    }

    func loadCachedMemory(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord? {
        try await memoryStore.load(ownerUserID: ownerUserID, memoryID: memoryID)
    }

    func requireMemory(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord {
        guard let existing = try await memoryStore.load(ownerUserID: ownerUserID, memoryID: memoryID) else {
            throw MemoryDataServiceError.missingMemory
        }
        return existing
    }

    func enqueue<Payload: Encodable>(
        ownerUserID: UUID,
        operation: SyncClientOperation,
        kind: SyncPendingOperationKind,
        scope: String,
        payload: Payload
    ) async throws {
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: kind,
                idempotencyScope: scope,
                requestData: try encoder.encode(payload)
            )
        )
    }

    func record(
        from existing: MemoryRecord,
        operation: SyncClientOperation,
        syncStatus: SyncRecordStatus,
        title: String? = nil,
        memoryDate: String? = nil,
        deletedAt: Date? = nil,
        lastEditedByUserID: UUID? = nil,
        ownNote: MemoryNoteSnapshot? = nil,
        visibleMemoryMediaIDs: [UUID]? = nil,
        visibleMediaAssetIDs: [UUID]? = nil,
        media: [MemoryMediaSnapshot]? = nil
    ) -> MemoryRecord {
        let snapshot = existing.snapshot
        return MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: snapshot.ownerUserID,
                memoryID: snapshot.memoryID,
                coupleID: snapshot.coupleID,
                title: title ?? snapshot.title,
                memoryDate: memoryDate ?? snapshot.memoryDate,
                createdByUserID: snapshot.createdByUserID,
                lastEditedByUserID: lastEditedByUserID ?? snapshot.lastEditedByUserID,
                revision: snapshot.revision,
                moderationStatus: snapshot.moderationStatus,
                deletedAt: deletedAt ?? snapshot.deletedAt,
                createdAt: snapshot.createdAt,
                updatedAt: operation.localCreatedAt,
                syncUpdatedAt: operation.localCreatedAt,
                ownNote: ownNote ?? snapshot.ownNote,
                partnerNote: snapshot.partnerNote,
                visibleMemoryMediaIDs: visibleMemoryMediaIDs ?? snapshot.visibleMemoryMediaIDs,
                visibleMediaAssetIDs: visibleMediaAssetIDs ?? snapshot.visibleMediaAssetIDs,
                media: media ?? snapshot.media,
                threadID: snapshot.threadID
            ),
            syncStatus: syncStatus,
            pendingOperationID: operation.id,
            conflictReason: nil,
            localUpdatedAt: operation.localCreatedAt
        )
    }

    static func normalizedRequired(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedOptional(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }

        return normalized
    }
}

nonisolated enum MemoryDataServiceFactory {
    static func makeDefault() -> any MemoryDataServicing {
        do {
            let localStore = try PaeoniaLocalStore()
            return MemoryDataService(
                memoryStore: SwiftDataMemoryRecordRepository(container: localStore.container),
                pendingOperationStore: SwiftDataPendingSyncOperationRepository(container: localStore.container)
            )
        } catch {
            return MemoryDataService(
                memoryStore: InMemoryMemoryRecordRepository(),
                pendingOperationStore: InMemoryPendingSyncOperationRepository()
            )
        }
    }
}
