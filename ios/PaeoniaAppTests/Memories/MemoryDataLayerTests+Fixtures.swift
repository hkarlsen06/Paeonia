import Foundation
import Testing
@testable import PaeoniaApp

extension MemoryDataLayerTests {
    struct RemoteMemoryFixture {
        let repository = InMemoryMemoryRecordRepository()
        let ownerUserID: UUID
        let memoryID: UUID
        let coupleID: UUID

        func load() async throws -> MemoryRecord? {
            try await repository.load(ownerUserID: ownerUserID, memoryID: memoryID)
        }
    }

    struct SeededMemory {
        let service: MemoryDataService
        let pendingStore: InMemoryPendingSyncOperationRepository
        let ownerUserID: UUID
        let memoryID: UUID
        let revision: Int
        let ownNoteRevision: Int?

        func queued(_ kind: SyncPendingOperationKind) async throws -> [PendingSyncOperationSnapshot] {
            try await pendingStore.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
        }

        func queuedPayloads<Payload: Decodable>(
            _ kind: SyncPendingOperationKind,
            as type: Payload.Type
        ) async throws -> [Payload] {
            try await queued(kind).map { operation in
                try #require(operation.requestData).decoded(as: type)
            }
        }
    }

    func update(
        _ seeded: SeededMemory,
        expectedRevision: Int,
        title: String,
        memoryDate: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        try await seeded.service.updateMemory(
            ownerUserID: seeded.ownerUserID,
            memoryID: seeded.memoryID,
            expectedRevision: expectedRevision,
            title: title,
            memoryDate: memoryDate,
            operation: operation
        )
    }

    func upsertNote(
        _ seeded: SeededMemory,
        expectedRevision: Int?,
        body: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        try await seeded.service.upsertMemoryNote(
            ownerUserID: seeded.ownerUserID,
            memoryID: seeded.memoryID,
            expectedRevision: expectedRevision,
            body: body,
            operation: operation
        )
    }

    func remoteFixture() throws -> RemoteMemoryFixture {
        RemoteMemoryFixture(
            ownerUserID: try fixedUUID("11111111-1111-1111-1111-111111111111"),
            memoryID: try fixedUUID("22222222-2222-2222-2222-222222222222"),
            coupleID: try fixedUUID("99999999-9999-9999-9999-999999999999")
        )
    }

    /// Saves one remote row. The row's sync time is `revision * 100` seconds, so a higher revision is always newer.
    func saveRemote(
        _ fixture: RemoteMemoryFixture,
        title: String,
        revision: Int,
        mergePolicy: MemoryRemoteMergePolicy
    ) async throws {
        try await fixture.repository.saveRemote(
            [
                remoteRow(
                    ownerUserID: fixture.ownerUserID,
                    memoryID: fixture.memoryID,
                    coupleID: fixture.coupleID,
                    title: title,
                    revision: revision,
                    syncUpdatedAt: Date(timeIntervalSince1970: TimeInterval(revision * 100))
                )
            ],
            ownerUserID: fixture.ownerUserID,
            mergePolicy: mergePolicy
        )
    }

    func seededMemory() async throws -> SeededMemory {
        let ownerUserID = try fixedUUID("11111111-1111-1111-1111-111111111111")
        let memoryID = try fixedUUID("33333333-3333-3333-3333-333333333333")
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(
            memoryStore: InMemoryMemoryRecordRepository(),
            pendingOperationStore: pendingStore
        )
        let created = try await service.createMemory(
            ownerUserID: ownerUserID,
            coupleID: try fixedUUID("22222222-2222-2222-2222-222222222222"),
            memoryID: memoryID,
            title: "Original",
            memoryDate: "2026-06-30",
            noteBody: "First note",
            operation: operation(id: "44444444-4444-4444-4444-444444444444", sequence: 1)
        )
        return SeededMemory(
            service: service,
            pendingStore: pendingStore,
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            revision: created.snapshot.revision,
            ownNoteRevision: created.snapshot.ownNote?.revision
        )
    }

    func record(
        from existing: MemoryRecord,
        title: String,
        syncStatus: SyncRecordStatus,
        pendingOperationID: UUID? = nil
    ) -> MemoryRecord {
        let snapshot = existing.snapshot
        return MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: snapshot.ownerUserID,
                memoryID: snapshot.memoryID,
                coupleID: snapshot.coupleID,
                title: title,
                memoryDate: snapshot.memoryDate,
                createdByUserID: snapshot.createdByUserID,
                lastEditedByUserID: snapshot.lastEditedByUserID,
                revision: snapshot.revision,
                moderationStatus: snapshot.moderationStatus,
                deletedAt: snapshot.deletedAt,
                createdAt: snapshot.createdAt,
                updatedAt: Date(timeIntervalSince1970: 150),
                syncUpdatedAt: Date(timeIntervalSince1970: 150),
                ownNote: snapshot.ownNote,
                partnerNote: snapshot.partnerNote,
                visibleMemoryMediaIDs: snapshot.visibleMemoryMediaIDs,
                visibleMediaAssetIDs: snapshot.visibleMediaAssetIDs,
                media: snapshot.media,
                threadID: snapshot.threadID
            ),
            syncStatus: syncStatus,
            pendingOperationID: pendingOperationID,
            localUpdatedAt: Date(timeIntervalSince1970: 150)
        )
    }

    func operation(id: String, sequence: Int64) throws -> SyncClientOperation {
        SyncClientOperation(
            id: try fixedUUID(id),
            clientID: try fixedUUID("99999999-9999-9999-9999-999999999999"),
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(100 + sequence))
        )
    }

    func remoteRow(
        ownerUserID: UUID,
        memoryID: UUID,
        coupleID: UUID,
        title: String,
        revision: Int = 1,
        syncUpdatedAt: Date
    ) -> MemoryRemoteRow {
        MemoryRemoteRow(
            memoryID: memoryID,
            coupleID: coupleID,
            title: title,
            memoryDate: "2026-06-30",
            createdByUserID: ownerUserID,
            lastEditedByUserID: ownerUserID,
            revision: revision,
            moderationStatus: .visible,
            deletedAt: nil,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: syncUpdatedAt,
            syncUpdatedAt: syncUpdatedAt,
            ownNoteID: nil,
            ownNoteBody: nil,
            ownNoteRevision: nil,
            ownNoteUpdatedAt: nil,
            ownNoteDeletedAt: nil,
            ownNoteModerationStatus: nil,
            partnerNoteID: nil,
            partnerNoteUserID: nil,
            partnerNoteBody: nil,
            partnerNoteRevision: nil,
            partnerNoteUpdatedAt: nil,
            partnerNoteDeletedAt: nil,
            partnerNoteModerationStatus: nil,
            memoryMediaIDs: [],
            mediaAssetIDs: [],
            memoryMediaStates: [],
            threadID: nil
        )
    }

    func fixedUUID(_ value: String) throws -> UUID {
        try #require(UUID(uuidString: value))
    }
}

extension Data {
    func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: self)
    }
}
