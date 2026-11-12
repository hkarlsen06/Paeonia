import Foundation
import Testing
@testable import PaeoniaApp

/// What else the join moves to the joined memory: comments written in the waiting memory's chat,
/// and the person's changes after the app ended in the middle of a join.
extension MemoryVisitJoinTests {
    @Test func commentsWrittenOnTheWaitingMemoryMoveToTheJoinedMemorysChatAsTheirs() async throws {
        let phone = try await phoneWithWaitingMemory()
        try await queueComment(
            CreateChatThreadPayload(subject: .memory(waitingID), coupleID: coupleID, body: "Miss you already"),
            .createChatThreadWithMessage, on: phone
        )
        try await queueComment(
            SendChatMessagePayload(
                subject: .memory(waitingID), coupleID: coupleID, threadID: nil, body: "Same flight next time?"
            ),
            .sendThreadMessage, on: phone
        )
        let create = try #require(try await phone.queued(.createMemory).first)

        _ = try await phone.createHandler.send(create, context: phone.context)

        let threads = try await phone.queued(.createChatThreadWithMessage)
        let sends = try await phone.queued(.sendThreadMessage)
        let decoder = JSONDecoder()
        let first = try threads.map { try decoder.decode(CreateChatThreadPayload.self, from: $0.requestData ?? Data()) }
        let later = try sends.map { try decoder.decode(SendChatMessagePayload.self, from: $0.requestData ?? Data()) }
        #expect(first.map(\.subject) == [.memory(joinedID)])
        #expect(first.map(\.body) == ["Miss you already"])
        #expect(later.map(\.subject) == [.memory(joinedID)])
        #expect(later.map(\.body) == ["Same flight next time?"])
        let firstAt = try #require(threads.first).operation.localCreatedAt
        let laterAt = try #require(sends.first).operation.localCreatedAt
        #expect(firstAt < laterAt)
    }

    @Test func aPhotoAddedAfterTheAppEndedMidJoinReachesTheJoinedMemory() async throws {
        let phone = try await phoneWithWaitingMemory()
        let first = Self.photo(owner: me, sortOrder: 2)
        _ = try await phone.service.attachMemoryMedia(
            ownerUserID: me, memoryID: waitingID, optimisticMedia: [first], operation: phone.nextOperation()
        )
        try await joinThenEndTheApp(phone)

        let second = Self.photo(owner: me, sortOrder: 3)
        _ = try await phone.service.attachMemoryMedia(
            ownerUserID: me, memoryID: waitingID, optimisticMedia: [second], operation: phone.nextOperation()
        )
        try await phone.drain()

        #expect(await phone.server.visiblePhotos(of: me) == [myPhoto, first.mediaAssetID, second.mediaAssetID])
        #expect(try await phone.isSettled())
    }

    @Test func aDeleteAfterTheAppEndedMidJoinTakesTheirNoteAndPhotosOffThePartnersMemory() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.upsertMemoryNote(
            ownerUserID: me, memoryID: waitingID, expectedRevision: nil, body: "Rain all week",
            operation: phone.nextOperation()
        )
        _ = try await phone.service.attachMemoryMedia(
            ownerUserID: me, memoryID: waitingID, optimisticMedia: [Self.photo(owner: me, sortOrder: 2)],
            operation: phone.nextOperation()
        )
        try await joinThenEndTheApp(phone)

        _ = try await phone.service.hideMemory(
            ownerUserID: me, memoryID: waitingID, expectedRevision: 1, operation: phone.nextOperation()
        )
        try await phone.drain()

        let server = phone.server
        #expect(await server.isDeleted == false)
        #expect(await server.notes[me] == nil)
        #expect(await server.visiblePhotos(of: me).isEmpty)
        #expect(await server.notes[partner]?.body == "Partner's note")
        #expect(await server.visiblePhotos(of: partner) == [partnerPhoto])
        #expect(try await phone.isSettled())
    }

    /// Sends the create, which joins, and ends the app after the join queued its writes and
    /// before it failed the old ones and removed the waiting copy.
    private func joinThenEndTheApp(_ phone: Phone) async throws {
        let create = try #require(try await phone.queued(.createMemory).first)
        let ending = HookedPendingStore(phone.pending) { throw HookedPendingStore.Crash() }
        let context = SyncContext(
            session: SyncSession(userID: me), reason: .manualRefresh, pendingOperationStore: ending
        )
        await #expect(throws: HookedPendingStore.Crash.self) {
            _ = try await phone.createHandler.send(create, context: context)
        }
        #expect(try await phone.store.load(ownerUserID: me, memoryID: waitingID) != nil)
    }

    private func queueComment(
        _ payload: some Encodable,
        _ kind: SyncPendingOperationKind,
        on phone: Phone
    ) async throws {
        try await phone.pending.enqueue(PendingSyncOperationRequest(
            ownerUserID: me, operation: phone.nextOperation(), operationKind: kind,
            idempotencyScope: "thread-chat:\(waitingID.uuidString.lowercased())",
            requestData: try JSONEncoder().encode(payload)
        ))
    }
}
