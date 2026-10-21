import Foundation

/// Sends a queued delete of a chat message the user took back. The chat already shows the
/// message as deleted. A delete that goes through changes nothing on this phone, except for
/// a message whose send had to finish first, which then shows as deleted here too.
struct DeleteChatMessageOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .deleteThreadMessage

    private let gateway: any ThreadChatGateway
    private let cache: any ThreadChatCaching
    private let mediaCache: (any DailyAnswerMediaCacheEvicting)?

    init(
        gateway: any ThreadChatGateway,
        cache: any ThreadChatCaching,
        mediaCache: (any DailyAnswerMediaCacheEvicting)? = nil
    ) {
        self.gateway = gateway
        self.cache = cache
        self.mediaCache = mediaCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData else {
            return .terminalFailure("Missing chat message delete payload")
        }
        let payload = try JSONDecoder().decodeQueuedPayload(DeleteChatMessagePayload.self, from: data)
        let messageID: UUID
        switch try await resolve(payload, operation: operation, context: context) {
        case .waitForSend: return .retry(after: nil)
        case .nothingToDelete: return .succeeded
        case let .delete(id): messageID = id
        }
        do {
            try await gateway.deleteMessage(messageID: messageID, operation: operation.operation)
        } catch {
            guard isPermanentDeleteFailure(error) else { throw error }
            return .terminalFailure("The chat message can't be deleted by this person")
        }
        if case .sentBy = payload.target { await showAsDeleted(messageID, payload: payload, operation: operation) }
        return .succeeded
    }

    private enum Resolution {
        case delete(messageID: UUID)
        case waitForSend
        case nothingToDelete
    }

    private func resolve(
        _ payload: DeleteChatMessagePayload,
        operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Resolution {
        switch payload.target {
        case let .message(id):
            return .delete(messageID: id)
        case let .sentBy(sendOperationID):
            return try await resolveSend(sendOperationID, payload: payload, operation: operation, context: context)
        }
    }

    /// Finds the message a tried send made. A copy in the chat cache means the server has it,
    /// whether the send's answer came back or the live query delivered the message first.
    /// Without one, a send still in the queue may yet reach the server, and one that is gone
    /// from the queue never did.
    private func resolveSend(
        _ sendOperationID: UUID,
        payload: DeleteChatMessagePayload,
        operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Resolution {
        let cached = await cache.messages(ownerUserID: operation.ownerUserID, subjectID: payload.subjectID)
        if let sent = cached.first(where: {
            $0.clientOperationID == sendOperationID && !$0.isSending && !$0.sendFailed
        }) {
            return .delete(messageID: sent.id)
        }
        for kind in [SyncPendingOperationKind.createChatThreadWithMessage, .sendThreadMessage] {
            let waiting = try await context.pendingOperationStore.inFlightOperations(
                ownerUserID: operation.ownerUserID,
                kind: kind
            )
            if waiting.contains(where: { $0.operation.id == sendOperationID }) { return .waitForSend }
        }
        return .nothingToDelete
    }

    private func showAsDeleted(
        _ messageID: UUID,
        payload: DeleteChatMessagePayload,
        operation: PendingSyncOperationSnapshot
    ) async {
        let mediaAssetIDs = await cache.markDeleted(
            ownerUserID: operation.ownerUserID,
            subjectID: payload.subjectID,
            messageID: messageID,
            at: operation.operation.localCreatedAt
        )
        if !mediaAssetIDs.isEmpty { await mediaCache?.evict(mediaAssetIDs: mediaAssetIDs) }
        LocalStoreChanges.post(.threadChat, ownerUserID: operation.ownerUserID)
    }

    /// Server rejections that trying again cannot fix. The Convex client puts the
    /// server's message in the error's description. A lost connection stays retryable.
    private nonisolated func isPermanentDeleteFailure(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return [
            "only the sender can delete a message",
            "active entitled thread access is required"
        ].contains { description.contains($0) }
    }
}
