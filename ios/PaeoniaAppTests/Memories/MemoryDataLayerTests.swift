import Foundation
import Testing
@testable import PaeoniaApp

struct MemoryDataLayerTests {
    @Test func repositoryPreservesDirtyLocalRecordDuringNormalPull() async throws {
        let ownerUserID = try fixedUUID("11111111-1111-1111-1111-111111111111")
        let memoryID = try fixedUUID("22222222-2222-2222-2222-222222222222")
        let coupleID = try fixedUUID("99999999-9999-9999-9999-999999999999")
        let repository = InMemoryMemoryRecordRepository()

        try await repository.saveRemote(
            [
                remoteRow(
                    ownerUserID: ownerUserID,
                    memoryID: memoryID,
                    coupleID: coupleID,
                    title: "Server title",
                    revision: 1,
                    syncUpdatedAt: Date(timeIntervalSince1970: 100)
                )
            ],
            ownerUserID: ownerUserID,
            preserveDirtyRecords: false
        )

        let localEdit = try #require(await repository.load(ownerUserID: ownerUserID, memoryID: memoryID))
        try await repository.saveLocal(record(from: localEdit, title: "Local title", syncStatus: .dirty))

        try await repository.saveRemote(
            [
                remoteRow(
                    ownerUserID: ownerUserID,
                    memoryID: memoryID,
                    coupleID: coupleID,
                    title: "Server changed title",
                    revision: 2,
                    syncUpdatedAt: Date(timeIntervalSince1970: 200)
                )
            ],
            ownerUserID: ownerUserID,
            preserveDirtyRecords: true
        )

        let preserved = try #require(await repository.load(ownerUserID: ownerUserID, memoryID: memoryID))
        #expect(preserved.snapshot.title == "Local title")
        #expect(preserved.syncStatus == .dirty)

        try await repository.saveRemote(
            [
                remoteRow(
                    ownerUserID: ownerUserID,
                    memoryID: memoryID,
                    coupleID: coupleID,
                    title: "Server changed title",
                    revision: 2,
                    syncUpdatedAt: Date(timeIntervalSince1970: 200)
                )
            ],
            ownerUserID: ownerUserID,
            preserveDirtyRecords: false
        )

        let replaced = try #require(await repository.load(ownerUserID: ownerUserID, memoryID: memoryID))
        #expect(replaced.snapshot.title == "Server changed title")
        #expect(replaced.syncStatus == .clean)
    }

    @Test func dataServiceCreateMemorySavesLocalRecordAndQueuesOperation() async throws {
        let ownerUserID = try fixedUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = try fixedUUID("22222222-2222-2222-2222-222222222222")
        let memoryID = try fixedUUID("33333333-3333-3333-3333-333333333333")
        let operation = SyncClientOperation(
            id: try fixedUUID("44444444-4444-4444-4444-444444444444"),
            clientID: try fixedUUID("55555555-5555-5555-5555-555555555555"),
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let memoryStore = InMemoryMemoryRecordRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(
            memoryStore: memoryStore,
            pendingOperationStore: pendingStore
        )

        let record = try await service.createMemory(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            memoryID: memoryID,
            title: "  First trip  ",
            memoryDate: "2026-06-30",
            noteBody: "  We made it.  ",
            optimisticMedia: [],
            operation: operation
        )

        #expect(record.snapshot.title == "First trip")
        #expect(record.snapshot.ownNote?.body == "We made it.")
        #expect(record.syncStatus == .dirty)
        #expect(record.pendingOperationID == operation.id)

        let cached = try #require(await memoryStore.load(ownerUserID: ownerUserID, memoryID: memoryID))
        #expect(cached.snapshot.title == "First trip")

        let operations = try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createMemory
        )
        let queued = try #require(operations.first)
        let payload = try #require(queued.requestData).decoded(as: CreateMemoryOperationPayload.self)
        #expect(payload.memoryID == memoryID)
        #expect(payload.title == "First trip")
        #expect(payload.noteBody == "We made it.")
    }

    @Test func memorySyncStreamStoresPulledRowsAndAdvancesCursor() async throws {
        let ownerUserID = try fixedUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = try fixedUUID("22222222-2222-2222-2222-222222222222")
        let firstMemoryID = try fixedUUID("33333333-3333-3333-3333-333333333333")
        let secondMemoryID = try fixedUUID("44444444-4444-4444-4444-444444444444")
        let firstRow = remoteRow(
            ownerUserID: ownerUserID,
            memoryID: firstMemoryID,
            coupleID: coupleID,
            title: "First",
            syncUpdatedAt: Date(timeIntervalSince1970: 100)
        )
        let secondRow = remoteRow(
            ownerUserID: ownerUserID,
            memoryID: secondMemoryID,
            coupleID: coupleID,
            title: "Second",
            syncUpdatedAt: Date(timeIntervalSince1970: 200)
        )
        let gateway = RecordingMemoryGateway(pages: [[firstRow, secondRow], []])
        let memoryStore = InMemoryMemoryRecordRepository()
        let stream = MemorySyncStream(
            gateway: gateway,
            memoryStore: memoryStore,
            pageSize: 2
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID, activeCoupleID: coupleID),
            reason: .startup,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let cursor = try await stream.pull(context: context)
        let cached = try await memoryStore.load(ownerUserID: ownerUserID, includeHidden: true)
        let requests = await gateway.requests

        #expect(Set(cached.map(\.snapshot.memoryID)) == Set([firstMemoryID, secondMemoryID]))
        #expect(cursor == SyncCursor(updatedAt: Date(timeIntervalSince1970: 200), tieID: secondMemoryID))
        #expect(requests.map(\.limit) == [2, 2])
        #expect(requests.last?.updatedAfter == Date(timeIntervalSince1970: 200))
        #expect(requests.last?.cursorMemoryID == secondMemoryID)
    }

    private func record(
        from existing: MemoryRecord,
        title: String,
        syncStatus: SyncRecordStatus
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
            pendingOperationID: nil,
            localUpdatedAt: Date(timeIntervalSince1970: 150)
        )
    }

    private func remoteRow(
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

    private func fixedUUID(_ value: String) throws -> UUID {
        try #require(UUID(uuidString: value))
    }
}

private actor RecordingMemoryGateway: SupabaseMemoryGateway {
    struct Request: Equatable {
        let updatedAfter: Date?
        let cursorMemoryID: UUID?
        let limit: Int
    }

    private var pages: [[MemoryRemoteRow]]
    private var recordedRequests: [Request] = []

    init(pages: [[MemoryRemoteRow]]) {
        self.pages = pages
    }

    var requests: [Request] {
        recordedRequests
    }

    func loadMemories(
        updatedAfter: Date?,
        cursorMemoryID: UUID?,
        limit: Int
    ) async throws -> [MemoryRemoteRow] {
        recordedRequests.append(
            Request(
                updatedAfter: updatedAfter,
                cursorMemoryID: cursorMemoryID,
                limit: limit
            )
        )
        guard !pages.isEmpty else {
            return []
        }
        return pages.removeFirst()
    }

    func createMemory(
        _ payload: CreateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID {
        payload.memoryID
    }

    func updateMemory(
        _ payload: UpdateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse? {
        nil
    }

    func hideMemory(
        _ payload: HideMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse? {
        nil
    }

    func upsertMemoryNote(
        _ payload: UpsertMemoryNoteOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryNoteRevisionResponse? {
        nil
    }

    func attachMemoryMedia(
        _ payload: AttachMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> [UUID] {
        payload.optimisticMedia.map(\.memoryMediaID)
    }

    func removeMemoryMedia(
        _ payload: RemoveMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID {
        payload.memoryMediaID
    }

    func createMemoryThreadWithMessage(
        _ payload: CreateMemoryThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryThreadMessageResponse? {
        nil
    }
}

private extension Data {
    func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: self)
    }
}
