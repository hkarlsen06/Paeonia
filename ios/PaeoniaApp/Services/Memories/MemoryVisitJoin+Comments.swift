import Foundation

extension MemoryPendingOperationRefresh {
    /// Comments the person wrote in the waiting memory's chat go to the joined memory's chat as
    /// theirs, with the same text, photos, voice and time. The server never had the waiting memory,
    /// so it would refuse them there. It adds them to the joined memory's chat if it has one.
    nonisolated static func moveComments(
        from waitingID: UUID,
        to joinedID: UUID,
        owner: UUID,
        pendingStore: any PendingSyncOperationPersisting
    ) async throws {
        for kind in [SyncPendingOperationKind.createChatThreadWithMessage, .sendThreadMessage] {
            for comment in try await pendingStore.inFlightOperations(ownerUserID: owner, kind: kind) {
                guard let data = comment.requestData,
                      let moved = try movedComment(data, kind: kind, from: waitingID, to: joinedID)
                else { continue }
                try await pendingStore.enqueue(PendingSyncOperationRequest(
                    ownerUserID: owner,
                    operation: movedOperation(comment.operation, to: joinedID),
                    operationKind: kind,
                    idempotencyScope: "thread-chat:\(joinedID.uuidString.lowercased())",
                    requestData: moved
                ))
                try await pendingStore.markTerminalFailure(
                    clientOperationID: comment.operation.id,
                    errorDescription: "The comment moved to the memory its visit memory joined",
                    at: Date()
                )
            }
        }
    }

    private nonisolated static func movedComment(
        _ data: Data,
        kind: SyncPendingOperationKind,
        from waitingID: UUID,
        to joinedID: UUID
    ) throws -> Data? {
        let joined = ThreadChatSubject.memory(joinedID)
        if kind == .createChatThreadWithMessage {
            guard let payload = try? JSONDecoder().decode(CreateChatThreadPayload.self, from: data),
                  payload.subject == .memory(waitingID) else { return nil }
            return try JSONEncoder().encode(CreateChatThreadPayload(
                subject: joined, coupleID: payload.coupleID, body: payload.body, voice: payload.voice,
                photos: payload.photos, replyToAnswerID: payload.replyToAnswerID,
                replyToGameResultSource: payload.replyToGameResultSource
            ))
        }
        guard let payload = try? JSONDecoder().decode(SendChatMessagePayload.self, from: data),
              payload.subject == .memory(waitingID) else { return nil }
        return try JSONEncoder().encode(SendChatMessagePayload(
            subject: joined, coupleID: payload.coupleID, threadID: payload.threadID, body: payload.body,
            voice: payload.voice, photos: payload.photos, replyTo: payload.replyTo
        ))
    }

    /// The same comment, keyed to the joined memory, so a join that runs again moves it once.
    private nonisolated static func movedOperation(_ original: SyncClientOperation, to joinedID: UUID)
        -> SyncClientOperation {
        SyncClientOperation(
            id: UUID(hashing: "\(original.id.uuidString)/to/\(joinedID.uuidString)"),
            clientID: original.clientID,
            clientSequence: original.clientSequence,
            localCreatedAt: original.localCreatedAt
        )
    }
}
