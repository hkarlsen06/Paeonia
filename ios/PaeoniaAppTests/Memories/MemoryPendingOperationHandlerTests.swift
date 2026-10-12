import Foundation
import Testing
@testable import PaeoniaApp

/// How queued memory writes settle when the partner got there first: a revision
/// conflict is rebased on the server copy instead of leaving the memory stuck, and a
/// write to a memory the partner deleted stops retrying and shows the deletion.
struct MemoryPendingOperationHandlerTests {
    private let ownerUserID = UUID()
    private let coupleID = UUID()
    private let memoryID = UUID()

    @Test func updateConflictKeepsThePartnersDateWhenOnlyTheTitleChanged() async throws {
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Partner title", memoryDate: "2026-07-01", revision: 5)],
            updateFailures: [conflict]
        )
        let handler = UpdateMemoryPendingOperationHandler(
            gateway: gateway,
            memoryStore: InMemoryMemoryRecordRepository()
        )
        let payload = UpdateMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: 3,
            title: "My title",
            memoryDate: "2026-06-30",
            baseTitle: "Old title",
            baseMemoryDate: "2026-06-30"
        )

        let result = try await handler.send(snapshot(.updateMemory, payload), context: context())

        #expect(result == .succeeded)
        let sent = await gateway.updates
        #expect(sent.count == 2)
        let rebased = try #require(sent.last)
        #expect(rebased.title == "My title")
        #expect(rebased.memoryDate == "2026-07-01")
        #expect(rebased.expectedRevision == 5)
    }

    @Test func updateConflictWithNothingLeftToChangeSucceedsWithoutResending() async throws {
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Same title", memoryDate: "2026-06-30", revision: 4)],
            updateFailures: [conflict]
        )
        let handler = UpdateMemoryPendingOperationHandler(
            gateway: gateway,
            memoryStore: InMemoryMemoryRecordRepository()
        )
        let payload = UpdateMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: 2,
            title: "Same title",
            memoryDate: "2026-06-30",
            baseTitle: "Old title",
            baseMemoryDate: "2026-06-30"
        )

        let result = try await handler.send(snapshot(.updateMemory, payload), context: context())

        #expect(result == .succeeded)
        #expect(await gateway.updates.count == 1)
    }

    @Test func aNoteForAMemoryThePartnerDeletedStopsRetryingAndShowsTheDeletion() async throws {
        let store = InMemoryMemoryRecordRepository()
        let service = MemoryDataService(
            memoryStore: store,
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
        try await store.saveRemote(
            [serverRow(title: "Trip", revision: 1)],
            ownerUserID: ownerUserID,
            mergePolicy: .overwriteLocalChanges
        )
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
        _ = try await service.upsertMemoryNote(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            expectedRevision: nil,
            body: "Written offline",
            operation: operation
        )
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Trip", revision: 2, deletedAt: Date(timeIntervalSince1970: 300))],
            noteFailures: [notWritable]
        )
        let handler = UpsertMemoryNotePendingOperationHandler(gateway: gateway, memoryStore: store)
        let payload = UpsertMemoryNoteOperationPayload(memoryID: memoryID, expectedRevision: 0, body: "Written offline")

        let result = try await handler.send(
            snapshot(.upsertMemoryNote, payload, operation: operation),
            context: context()
        )

        guard case .terminalFailure = result else {
            Issue.record("Expected the write to stop retrying, got \(result)")
            return
        }
        let local = try #require(await store.load(ownerUserID: ownerUserID, memoryID: memoryID))
        #expect(local.snapshot.deletedAt != nil)
        #expect(local.syncStatus == .clean)
    }

    @Test func aRefusedWriteToAMemoryThatStillExistsIsRetriedLater() async throws {
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Trip", revision: 1)],
            noteFailures: [notWritable]
        )
        let handler = UpsertMemoryNotePendingOperationHandler(
            gateway: gateway,
            memoryStore: InMemoryMemoryRecordRepository()
        )
        let payload = UpsertMemoryNoteOperationPayload(memoryID: memoryID, expectedRevision: 0, body: "Hello")

        await #expect(throws: PaeoniaConvexError.self) {
            try await handler.send(snapshot(.upsertMemoryNote, payload), context: context())
        }
    }

    /// A check on the server (here a title over the length limit) will never pass on a
    /// retry, so the write stops instead of holding up newer edits. The text stays on
    /// this phone for the person to shorten.
    @Test func aTitleTheServerRefusesStopsRetryingAndKeepsTheText() async throws {
        let store = InMemoryMemoryRecordRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(memoryStore: store, pendingOperationStore: pendingStore)
        try await store.saveRemote(
            [serverRow(title: "Trip", revision: 1)],
            ownerUserID: ownerUserID,
            mergePolicy: .overwriteLocalChanges
        )
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
        _ = try await service.updateMemory(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            expectedRevision: 1,
            title: "Edited title",
            memoryDate: "2026-06-30",
            operation: operation
        )
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Trip", revision: 1)],
            updateFailures: [PaeoniaConvexError.server(code: "23514", message: "memory title is too long")]
        )
        let handler = UpdateMemoryPendingOperationHandler(gateway: gateway, memoryStore: store)
        let payload = UpdateMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: 1,
            title: "Edited title",
            memoryDate: "2026-06-30",
            baseTitle: "Trip",
            baseMemoryDate: "2026-06-30"
        )

        let result = try await handler.send(
            snapshot(.updateMemory, payload, operation: operation),
            context: context()
        )

        guard case .terminalFailure = result else {
            Issue.record("Expected the write to stop retrying, got \(result)")
            return
        }
        let local = try #require(await store.load(ownerUserID: ownerUserID, memoryID: memoryID))
        #expect(local.snapshot.title == "Edited title")
    }

    @Test func deleteConflictStillDeletesAtTheServersRevision() async throws {
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Partner edit", revision: 7)],
            hideFailures: [conflict]
        )
        let handler = HideMemoryPendingOperationHandler(
            gateway: gateway,
            memoryStore: InMemoryMemoryRecordRepository()
        )
        let payload = HideMemoryOperationPayload(memoryID: memoryID, expectedRevision: 6)

        let result = try await handler.send(snapshot(.hideMemory, payload), context: context())

        #expect(result == .succeeded)
        #expect(await gateway.hides.map(\.expectedRevision) == [6, 7])
    }

    @Test func removingAPhotoThatIsAlreadyGoneSucceeds() async throws {
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Trip", revision: 1)],
            removeFailures: [notWritable]
        )
        let handler = RemoveMemoryMediaPendingOperationHandler(
            gateway: gateway,
            memoryStore: InMemoryMemoryRecordRepository()
        )
        let payload = RemoveMemoryMediaOperationPayload(memoryID: memoryID, memoryMediaID: UUID())

        let result = try await handler.send(snapshot(.removeMemoryMedia, payload), context: context())

        #expect(result == .succeeded)
    }

    @Test func aNewerEditWaitsForAnOlderEditThatIsRetrying() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let clientID = UUID()
        let olderRetry = Date(timeIntervalSinceNow: 60)
        try await enqueueRetryingUpdate(
            title: "Beach",
            operation: SyncClientOperation(clientID: clientID, clientSequence: 1),
            retryAt: olderRetry,
            in: pendingStore
        )
        let gateway = ScriptedMemoryGateway(rows: [serverRow(title: "Original", revision: 1)])
        let handler = UpdateMemoryPendingOperationHandler(
            gateway: gateway,
            memoryStore: InMemoryMemoryRecordRepository()
        )
        let newerPayload = UpdateMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: 2,
            title: "Holiday",
            memoryDate: "2026-06-30",
            baseTitle: nil,
            baseMemoryDate: "2026-06-01"
        )
        let newer = SyncClientOperation(
            clientID: clientID,
            clientSequence: 2,
            localCreatedAt: Date(timeIntervalSinceNow: 1)
        )

        let result = try await handler.send(
            snapshot(.updateMemory, newerPayload, operation: newer),
            context: context(pendingStore: pendingStore)
        )

        #expect(result == .retry(after: olderRetry))
        #expect(await gateway.updates.isEmpty)
    }

    @Test func anEditBasedOnAnOutdatedReadIsRefusedLocally() async throws {
        let store = InMemoryMemoryRecordRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(memoryStore: store, pendingOperationStore: pendingStore)
        try await store.saveRemote(
            [serverRow(title: "Partner's newer title", revision: 2)],
            ownerUserID: ownerUserID,
            mergePolicy: .overwriteLocalChanges
        )

        await #expect(throws: MemoryDataServiceError.staleRevision) {
            try await service.updateMemory(
                ownerUserID: ownerUserID,
                memoryID: memoryID,
                expectedRevision: 1,
                title: "Old title",
                memoryDate: "2026-07-01",
                operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
            )
        }
        #expect(try await pendingStore.inFlightOperations(ownerUserID: ownerUserID, kind: .updateMemory).isEmpty)
    }
}

// MARK: - Fixtures

extension MemoryPendingOperationHandlerTests {
    private var conflict: PaeoniaConvexError {
        .server(code: "40001", message: "memory revision conflict")
    }

    private var notWritable: PaeoniaConvexError {
        .server(code: "42501", message: "active entitled memory access is required")
    }

    private func serverRow(
        title: String,
        memoryDate: String = "2026-06-30",
        revision: Int,
        deletedAt: Date? = nil
    ) -> MemoryRemoteRow {
        .fixture(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            coupleID: coupleID,
            title: title,
            memoryDate: memoryDate,
            revision: revision,
            deletedAt: deletedAt,
            syncUpdatedAt: Date(timeIntervalSince1970: 200)
        )
    }

    private func snapshot(
        _ kind: SyncPendingOperationKind,
        _ payload: some Encodable,
        operation: SyncClientOperation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
    ) throws -> PendingSyncOperationSnapshot {
        PendingSyncOperationSnapshot(
            ownerUserID: ownerUserID,
            operation: operation,
            operationKind: kind,
            idempotencyScope: "memory",
            requestHash: nil,
            requestData: try JSONEncoder().encode(payload),
            status: .queued,
            attemptCount: 0,
            lastAttemptAt: nil,
            nextRetryAt: nil,
            lastError: nil,
            completedAt: nil
        )
    }

    private func enqueueRetryingUpdate(
        title: String,
        operation: SyncClientOperation,
        retryAt: Date,
        in pendingStore: InMemoryPendingSyncOperationRepository
    ) async throws {
        let payload = UpdateMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: 1,
            title: title,
            memoryDate: "2026-06-30",
            baseTitle: nil,
            baseMemoryDate: "2026-06-01"
        )
        try await pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .updateMemory,
                idempotencyScope: "memory",
                requestData: try JSONEncoder().encode(payload)
            )
        )
        try await pendingStore.markRetryableFailure(
            clientOperationID: operation.id,
            errorDescription: "offline",
            nextRetryAt: retryAt,
            at: Date()
        )
    }

    private func context(
        pendingStore: any PendingSyncOperationPersisting = InMemoryPendingSyncOperationRepository()
    ) -> SyncContext {
        SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )
    }
}

/// A gateway that fails each kind of write with the given errors, in order, and then
/// succeeds. `loadMemories` returns `rows` once, as the server's only page.
private actor ScriptedMemoryGateway: MemoryGateway {
    private let rows: [MemoryRemoteRow]
    private var updateFailures: [PaeoniaConvexError]
    private var hideFailures: [PaeoniaConvexError]
    private var noteFailures: [PaeoniaConvexError]
    private var removeFailures: [PaeoniaConvexError]
    private(set) var updates: [UpdateMemoryOperationPayload] = []
    private(set) var hides: [HideMemoryOperationPayload] = []

    init(
        rows: [MemoryRemoteRow],
        updateFailures: [PaeoniaConvexError] = [],
        hideFailures: [PaeoniaConvexError] = [],
        noteFailures: [PaeoniaConvexError] = [],
        removeFailures: [PaeoniaConvexError] = []
    ) {
        self.rows = rows
        self.updateFailures = updateFailures
        self.hideFailures = hideFailures
        self.noteFailures = noteFailures
        self.removeFailures = removeFailures
    }

    func loadMemories(updatedAfter: Date?, cursorMemoryID: UUID?, limit: Int) throws -> [MemoryRemoteRow] {
        updatedAfter == nil ? rows : []
    }

    func createMemory(_ payload: CreateMemoryOperationPayload, operation: SyncClientOperation) throws -> UUID {
        payload.memoryID
    }

    func updateMemory(
        _ payload: UpdateMemoryOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryRevisionResponse? {
        updates.append(payload)
        if !updateFailures.isEmpty { throw updateFailures.removeFirst() }
        return nil
    }

    func hideMemory(
        _ payload: HideMemoryOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryRevisionResponse? {
        hides.append(payload)
        if !hideFailures.isEmpty { throw hideFailures.removeFirst() }
        return nil
    }

    func upsertMemoryNote(
        _ payload: UpsertMemoryNoteOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryNoteRevisionResponse? {
        if !noteFailures.isEmpty { throw noteFailures.removeFirst() }
        return nil
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
        if !removeFailures.isEmpty { throw removeFailures.removeFirst() }
        return payload.memoryMediaID
    }

    func createMemoryThreadWithMessage(
        _ payload: CreateMemoryThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryThreadMessageResponse? {
        nil
    }
}
