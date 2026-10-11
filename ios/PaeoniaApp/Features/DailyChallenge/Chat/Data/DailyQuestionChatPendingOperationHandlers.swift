import Foundation

struct CreateDailyQuestionThreadMessagePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createDailyQuestionThreadWithMessage

    private let gateway: any DailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching

    init(
        gateway: any DailyQuestionChatGateway,
        cache: any DailyQuestionChatCaching
    ) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData else {
            return .terminalFailure("Missing daily question thread payload")
        }
        let payload = try JSONDecoder().decode(
            CreateDailyQuestionThreadMessageOperationPayload.self,
            from: data
        )
        let response: DailyQuestionThreadMessageResponse
        do {
            response = try await gateway.createThreadWithMessage(
                payload,
                operation: operation.operation
            )
        } catch {
            guard isPermanentChatFailure(error) else { throw error }
            await markChatMessageFailed(operation, cache: cache)
            try await failMessagesWaitingForThread(of: payload.instanceID, operation, context: context)
            return .terminalFailure("Daily question chat is no longer available")
        }
        await cache.confirm(
            ownerUserID: operation.ownerUserID,
            instanceID: payload.instanceID,
            coupleID: payload.coupleID,
            clientOperationID: operation.operation.id,
            threadID: response.threadID,
            messageID: response.messageID,
            body: payload.body,
            senderUserID: operation.ownerUserID,
            createdAt: operation.operation.localCreatedAt
        )
        LocalStoreChanges.post(.dailyChat, ownerUserID: operation.ownerUserID)
        return .succeeded
    }

    /// Messages queued while this thread was being created wait for its id. The
    /// thread will never exist now, so they would wait forever. Show them as failed,
    /// so the person can send them again.
    private func failMessagesWaitingForThread(
        of instanceID: UUID,
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws {
        let store = context.pendingOperationStore
        let sends = try await store.inFlightOperations(ownerUserID: operation.ownerUserID, kind: .sendThreadMessage)
        for waiting in sends {
            guard let data = waiting.requestData,
                  let payload = try? JSONDecoder().decode(
                    SendDailyQuestionThreadMessageOperationPayload.self,
                    from: data
                  ),
                  payload.instanceID == instanceID,
                  payload.threadID == nil
            else { continue }
            await markChatMessageFailed(waiting, cache: cache)
            try await store.markTerminalFailure(
                clientOperationID: waiting.operation.id,
                errorDescription: "The chat this message waited for was refused",
                at: Date()
            )
        }
    }
}

struct SendDailyQuestionThreadMessagePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .sendThreadMessage

    private let gateway: any DailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching

    init(
        gateway: any DailyQuestionChatGateway,
        cache: any DailyQuestionChatCaching
    ) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData else {
            return .terminalFailure("Missing thread message payload")
        }
        let payload = try JSONDecoder().decode(
            SendDailyQuestionThreadMessageOperationPayload.self,
            from: data
        )
        let cachedThreadID = await cache.summaries(ownerUserID: operation.ownerUserID)
            .first(where: { $0.instanceID == payload.instanceID })?.threadID
        guard let threadID = payload.threadID ?? cachedThreadID else {
            return .retry(after: nil)
        }

        let response: DailyQuestionThreadMessageResponse
        do {
            response = try await gateway.sendMessage(
                threadID: threadID,
                body: payload.body,
                operation: operation.operation
            )
        } catch {
            guard isPermanentChatFailure(error) else { throw error }
            await markChatMessageFailed(operation, cache: cache)
            return .terminalFailure("Thread message was rejected")
        }
        await cache.confirm(
            ownerUserID: operation.ownerUserID,
            instanceID: payload.instanceID,
            coupleID: payload.coupleID,
            clientOperationID: operation.operation.id,
            threadID: response.threadID,
            messageID: response.messageID,
            body: payload.body,
            senderUserID: operation.ownerUserID,
            createdAt: operation.operation.localCreatedAt
        )
        LocalStoreChanges.post(.dailyChat, ownerUserID: operation.ownerUserID)
        return .succeeded
    }
}

/// Server rejections that sending again cannot fix. The Convex client puts the
/// server's message in the error's description. Everything else, such as a lost
/// connection, stays retryable.
private nonisolated func isPermanentChatFailure(_ error: any Error) -> Bool {
    let description = String(describing: error).lowercased()
    return [
        "you must answer this daily question",
        "daily question thread requires both partners",
        "daily question instance was not found",
        "message sender must be an active visible thread member",
        "thread message body is too long"
    ].contains { description.contains($0) }
}

/// Shows the message as failed in the open chat. The drain records the operation
/// as finished after the handler returns.
private func markChatMessageFailed(
    _ operation: PendingSyncOperationSnapshot,
    cache: any DailyQuestionChatCaching
) async {
    await cache.markFailed(
        ownerUserID: operation.ownerUserID,
        clientOperationID: operation.operation.id
    )
    LocalStoreChanges.post(.dailyChat, ownerUserID: operation.ownerUserID)
}
