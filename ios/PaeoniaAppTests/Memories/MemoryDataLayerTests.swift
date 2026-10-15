import Foundation
import Testing
@testable import PaeoniaApp

struct MemoryDataLayerTests {
    @Test func repositoryPreservesDirtyLocalRecordDuringNormalPull() async throws {
        let fixture = try remoteFixture()

        try await saveRemote(fixture, title: "Server title", revision: 1, mergePolicy: .overwriteLocalChanges)

        let localEdit = try #require(await fixture.load())
        try await fixture.repository.saveLocal(record(from: localEdit, title: "Local title", syncStatus: .dirty))

        try await saveRemote(fixture, title: "Server changed title", revision: 2, mergePolicy: .preserveLocalChanges)

        let preserved = try #require(await fixture.load())
        #expect(preserved.snapshot.title == "Local title")
        #expect(preserved.syncStatus == .dirty)

        try await saveRemote(fixture, title: "Server changed title", revision: 2, mergePolicy: .overwriteLocalChanges)

        let replaced = try #require(await fixture.load())
        #expect(replaced.snapshot.title == "Server changed title")
        #expect(replaced.syncStatus == .clean)
    }

    @Test func repositoryOperationRefreshOnlyOverwritesTheConfirmedLocalOperation() async throws {
        let fixture = try remoteFixture()
        let firstOperationID = try fixedUUID("33333333-3333-3333-3333-333333333333")
        let secondOperationID = try fixedUUID("44444444-4444-4444-4444-444444444444")

        try await saveRemote(fixture, title: "Original", revision: 1, mergePolicy: .overwriteLocalChanges)

        let cached = try #require(await fixture.load())
        try await fixture.repository.saveLocal(
            record(
                from: cached,
                title: "Second local edit",
                syncStatus: .dirty,
                pendingOperationID: secondOperationID
            )
        )

        try await saveRemote(
            fixture,
            title: "First operation on server",
            revision: 2,
            mergePolicy: .overwriteIfPendingOperationMatches(firstOperationID)
        )

        let preserved = try #require(await fixture.load())
        #expect(preserved.snapshot.title == "Second local edit")
        #expect(preserved.syncStatus == .dirty)
        #expect(preserved.pendingOperationID == secondOperationID)

        try await saveRemote(
            fixture,
            title: "Second operation on server",
            revision: 3,
            mergePolicy: .overwriteIfPendingOperationMatches(secondOperationID)
        )

        let replaced = try #require(await fixture.load())
        #expect(replaced.snapshot.title == "Second operation on server")
        #expect(replaced.snapshot.revision == 3)
        #expect(replaced.syncStatus == .clean)
        #expect(replaced.pendingOperationID == nil)
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

    @Test func dataServiceAdvancesLocalRevisionsForConsecutiveQueuedEdits() async throws {
        let seeded = try await seededMemory()
        let firstUpdate = try await update(
            seeded,
            expectedRevision: seeded.revision,
            title: "Second title",
            memoryDate: "2026-07-01",
            operation: try operation(id: "55555555-5555-5555-5555-555555555555", sequence: 2)
        )
        let secondUpdate = try await update(
            seeded,
            expectedRevision: firstUpdate.snapshot.revision,
            title: "Third title",
            memoryDate: "2026-07-02",
            operation: try operation(id: "66666666-6666-6666-6666-666666666666", sequence: 3)
        )
        let firstNote = try await upsertNote(
            seeded,
            expectedRevision: secondUpdate.snapshot.ownNote?.revision,
            body: "Second note",
            operation: try operation(id: "77777777-7777-7777-7777-777777777777", sequence: 4)
        )
        let secondNote = try await upsertNote(
            seeded,
            expectedRevision: firstNote.snapshot.ownNote?.revision,
            body: "Third note",
            operation: try operation(id: "88888888-8888-8888-8888-888888888888", sequence: 5)
        )

        #expect(seeded.revision == 1)
        #expect(seeded.ownNoteRevision == 1)
        #expect(firstUpdate.snapshot.revision == 2)
        #expect(secondUpdate.snapshot.revision == 3)
        #expect(firstNote.snapshot.ownNote?.revision == 2)
        #expect(secondNote.snapshot.ownNote?.revision == 3)

        let updatePayloads = try await seeded.queuedPayloads(.updateMemory, as: UpdateMemoryOperationPayload.self)
        let notePayloads = try await seeded.queuedPayloads(
            .upsertMemoryNote,
            as: UpsertMemoryNoteOperationPayload.self
        )
        #expect(updatePayloads.map(\.expectedRevision) == [1, 2])
        #expect(notePayloads.map(\.expectedRevision) == [1, 2])
    }
}

private actor RecordingMemoryGateway: MemoryGateway {
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
    ) throws -> [MemoryRemoteRow] {
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
    ) throws -> UUID {
        payload.memoryID
    }

    func updateMemory(
        _ payload: UpdateMemoryOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryRevisionResponse? {
        nil
    }

    func hideMemory(
        _ payload: HideMemoryOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryRevisionResponse? {
        nil
    }

    func upsertMemoryNote(
        _ payload: UpsertMemoryNoteOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryNoteRevisionResponse? {
        nil
    }

    func attachMemoryMedia(
        _ payload: AttachMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) throws -> [UUID] {
        payload.optimisticMedia.map(\.memoryMediaID)
    }

    func removeMemoryMedia(
        _ payload: RemoveMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) throws -> UUID {
        payload.memoryMediaID
    }

    func createMemoryThreadWithMessage(
        _ payload: CreateMemoryThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryThreadMessageResponse? {
        nil
    }
}
