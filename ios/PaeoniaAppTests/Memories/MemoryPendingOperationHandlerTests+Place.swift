import Foundation
import Testing
@testable import PaeoniaApp

/// A queued place goes to `set_memory_place`, and one for a deleted memory stops retrying.
extension MemoryPendingOperationHandlerTests {
    @Test func aPlaceIsSentAndTheServerCopyReplacesTheLocalOne() async throws {
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
        let place = MemoryPlace(
            name: "Bryggen",
            latitude: 60.3975,
            longitude: 5.3245,
            city: "Bergen",
            countryCode: "NO"
        )
        let local = try await service.setMemoryPlace(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            place: place,
            operation: operation
        )
        #expect(local.syncStatus == .dirty)
        #expect(local.snapshot.place == place)
        // A place change keeps the revision, so it never conflicts with a title edit.
        #expect(local.snapshot.revision == 1)

        let gateway = ScriptedMemoryGateway(rows: [serverRow(title: "Trip", revision: 1)])
        let handler = SetMemoryPlacePendingOperationHandler(gateway: gateway, memoryStore: store)
        let payload = SetMemoryPlaceOperationPayload(memoryID: memoryID, place: place)

        let result = try await handler.send(
            snapshot(.setMemoryPlace, payload, operation: operation),
            context: context()
        )

        #expect(result == .succeeded)
        #expect(await gateway.places == [payload])
        #expect(try await store.load(ownerUserID: ownerUserID, memoryID: memoryID)?.syncStatus == .clean)
    }

    @Test func aPlaceForAMemoryThePartnerDeletedStopsRetrying() async throws {
        let gateway = ScriptedMemoryGateway(
            rows: [serverRow(title: "Trip", revision: 2, deletedAt: Date(timeIntervalSince1970: 300))],
            placeFailures: [notWritable]
        )
        let handler = SetMemoryPlacePendingOperationHandler(
            gateway: gateway,
            memoryStore: InMemoryMemoryRecordRepository()
        )
        let payload = SetMemoryPlaceOperationPayload(memoryID: memoryID, place: nil)

        let result = try await handler.send(snapshot(.setMemoryPlace, payload), context: context())

        guard case .terminalFailure = result else {
            Issue.record("Expected the write to stop retrying, got \(result)")
            return
        }
    }

    // swiftlint:disable function_body_length
    /// A place waiting to retry stays on this phone when a later note goes through
    /// first, and the place's own success brings the record up to date.
    @Test func aPlaceWaitingToRetryStaysWhenALaterNoteGoesThrough() async throws {
    // swiftlint:enable function_body_length
        let store = InMemoryMemoryRecordRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(memoryStore: store, pendingOperationStore: pendingStore)
        try await store.saveRemote(
            [serverRow(title: "Trip", revision: 1)],
            ownerUserID: ownerUserID,
            mergePolicy: .overwriteLocalChanges
        )
        let placeOperation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
        let noteOperation = SyncClientOperation(clientID: UUID(), clientSequence: 2)
        _ = try await service.setMemoryPlace(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            place: .bryggen,
            operation: placeOperation
        )
        _ = try await service.upsertMemoryNote(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            expectedRevision: nil,
            body: "Cafés",
            operation: noteOperation
        )
        let gateway = ScriptedMemoryGateway(rows: [serverRow(title: "Trip", revision: 1)])

        let noteResult = try await UpsertMemoryNotePendingOperationHandler(gateway: gateway, memoryStore: store).send(
            snapshot(
                .upsertMemoryNote,
                UpsertMemoryNoteOperationPayload(memoryID: memoryID, expectedRevision: 0, body: "Cafés"),
                operation: noteOperation
            ),
            context: context(pendingStore: pendingStore)
        )

        #expect(noteResult == .succeeded)
        let waiting = try #require(await store.load(ownerUserID: ownerUserID, memoryID: memoryID))
        #expect(waiting.snapshot.place == .bryggen)
        #expect(waiting.syncStatus == .dirty)

        try await pendingStore.markSucceeded(clientOperationID: noteOperation.id, at: Date())
        let placeResult = try await SetMemoryPlacePendingOperationHandler(gateway: gateway, memoryStore: store).send(
            snapshot(
                .setMemoryPlace,
                SetMemoryPlaceOperationPayload(memoryID: memoryID, place: .bryggen),
                operation: placeOperation
            ),
            context: context(pendingStore: pendingStore)
        )

        #expect(placeResult == .succeeded)
        // Nothing else is waiting, so the server copy replaces the local one.
        #expect(try await store.load(ownerUserID: ownerUserID, memoryID: memoryID)?.syncStatus == .clean)
    }
}
