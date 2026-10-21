import Foundation

// Taking back a message. A message the server has is shown as deleted at once, and the
// delete waits in the send queue like a send does. A message that was never tried is pulled
// out of the queue, so it never reaches the partner. A message that was tried may already be
// on the server, so its delete waits in the queue behind the send.
extension ThreadChatService {
    func deleteMessage(
        ownerUserID: UUID,
        message: ThreadChatMessage,
        operation: SyncClientOperation
    ) async throws {
        if message.isUnsent {
            try await dropUnsentMessage(message, ownerUserID: ownerUserID, operation: operation)
        } else {
            try await queueDeletion(of: message, ownerUserID: ownerUserID, operation: operation)
        }
        LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
    }

    /// The messages the user took back whose delete the server has not confirmed. A server
    /// result that still shows one must not bring it back.
    func pendingDeletions(ownerUserID: UUID) async -> ThreadChatPendingDeletions {
        let operations = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .deleteThreadMessage
        )) ?? []
        var deletions = ThreadChatPendingDeletions()
        for operation in operations {
            guard let data = operation.requestData,
                  let payload = try? JSONDecoder().decode(DeleteChatMessagePayload.self, from: data)
            else { continue }
            let takenBackAt = operation.operation.localCreatedAt
            switch payload.target {
            case let .message(messageID):
                deletions.byMessageID[messageID] = min(deletions.byMessageID[messageID] ?? takenBackAt, takenBackAt)
            case let .sentBy(operationID):
                deletions.bySendOperationID[operationID] = min(
                    deletions.bySendOperationID[operationID] ?? takenBackAt,
                    takenBackAt
                )
            }
        }
        return deletions
    }

    /// The partner took a message back, and this phone heard it in a silent push. The cached
    /// chat shows it as deleted and loses its files, so an old message deleted while the
    /// chat is closed does not stay in the history this phone keeps.
    func applyRemoteDeletion(ownerUserID: UUID, messageID: UUID) async {
        let mediaAssetIDs = await cache.markDeletedInAnyChat(
            ownerUserID: ownerUserID,
            messageID: messageID,
            at: Date()
        )
        if !mediaAssetIDs.isEmpty { await mediaCache?.evict(mediaAssetIDs: mediaAssetIDs) }
        LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
    }

    /// A server result with the user's pending deletes applied. The photos and voice
    /// recordings of every message it shows as deleted leave this phone, whoever deleted
    /// them, so a deleted file does not stay in the cache on the partner's phone.
    func withDeletions(
        _ incoming: [ThreadChatMessage],
        cached: [ThreadChatMessage],
        ownerUserID: UUID
    ) async -> [ThreadChatMessage] {
        let shown = ThreadChatMessage.applyingDeletions(
            incoming,
            deletions: await pendingDeletions(ownerUserID: ownerUserID)
        )
        let removed = ThreadChatMessage.mediaAssetIDsDeleted(in: shown, comparedTo: cached)
        if !removed.isEmpty { await mediaCache?.evict(mediaAssetIDs: removed) }
        return shown
    }

    private func queueDeletion(
        of message: ThreadChatMessage,
        ownerUserID: UUID,
        operation: SyncClientOperation
    ) async throws {
        try await enqueueDeletion(
            DeleteChatMessagePayload(subjectID: message.subjectID, target: .message(message.id)),
            ownerUserID: ownerUserID,
            operation: operation
        )
        let mediaAssetIDs = await cache.markDeleted(
            ownerUserID: ownerUserID,
            subjectID: message.subjectID,
            messageID: message.id,
            at: operation.localCreatedAt
        )
        if !mediaAssetIDs.isEmpty { await mediaCache?.evict(mediaAssetIDs: mediaAssetIDs) }
    }

    private func enqueueDeletion(
        _ payload: DeleteChatMessagePayload,
        ownerUserID: UUID,
        operation: SyncClientOperation
    ) async throws {
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .deleteThreadMessage,
                idempotencyScope: "thread-chat:\(payload.subjectID.uuidString.lowercased())",
                requestData: try encoder.encode(payload)
            )
        )
    }

    /// Takes back a message the server has not confirmed. One that was never tried is
    /// removed from the queue and the chat, so it never goes out. One that was tried may be
    /// on the server already, because its answer can get lost, so the delete waits in the
    /// queue behind the send. A failed one is no longer in the queue, so only the chat copy goes.
    private func dropUnsentMessage(
        _ message: ThreadChatMessage,
        ownerUserID: UUID,
        operation: SyncClientOperation
    ) async throws {
        guard let operationID = message.clientOperationID else { return }
        if message.isSending {
            guard let waiting = try await waitingOperation(operationID, ownerUserID: ownerUserID),
                  waiting.status != .sending
            else { throw ThreadChatServiceError.stillSending }
            if waiting.attemptCount > 0 {
                try await enqueueDeletion(
                    DeleteChatMessagePayload(subjectID: message.subjectID, target: .sentBy(operationID: operationID)),
                    ownerUserID: ownerUserID,
                    operation: operation
                )
            } else {
                guard !(try await otherMessagesWaitForThread(
                        of: waiting,
                        subjectID: message.subjectID,
                        ownerUserID: ownerUserID
                      )),
                      try await pendingOperationStore.discardUnsent(clientOperationID: operationID)
                else { throw ThreadChatServiceError.stillSending }
            }
        }
        await cache.discardUnsent(
            ownerUserID: ownerUserID,
            subjectID: message.subjectID,
            clientOperationID: operationID
        )
    }

    private func waitingOperation(
        _ operationID: UUID,
        ownerUserID: UUID
    ) async throws -> PendingSyncOperationSnapshot? {
        for kind in [SyncPendingOperationKind.createChatThreadWithMessage, .sendThreadMessage] {
            let operations = try await pendingOperationStore.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
            if let found = operations.first(where: { $0.operation.id == operationID }) { return found }
        }
        return nil
    }

    /// The first message of a chat creates its thread, and messages queued after it wait for
    /// that thread. Taking the first one back would leave them waiting for good.
    private func otherMessagesWaitForThread(
        of operation: PendingSyncOperationSnapshot,
        subjectID: UUID,
        ownerUserID: UUID
    ) async throws -> Bool {
        guard operation.operationKind == .createChatThreadWithMessage else { return false }
        let sends = try await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .sendThreadMessage
        )
        return sends.contains { send in
            guard let data = send.requestData,
                  let payload = try? JSONDecoder().decode(SendChatMessagePayload.self, from: data)
            else { return false }
            return payload.subject.id == subjectID && payload.threadID == nil
        }
    }
}
