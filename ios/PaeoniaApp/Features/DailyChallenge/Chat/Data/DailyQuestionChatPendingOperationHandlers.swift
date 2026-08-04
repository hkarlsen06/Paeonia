import Foundation

struct CreateDailyQuestionThreadMessagePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createDailyQuestionThreadWithMessage

    private let gateway: any SupabaseDailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching

    init(
        gateway: any SupabaseDailyQuestionChatGateway,
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
            guard Self.isPermanentEligibilityFailure(error) else { throw error }
            await cache.markFailed(
                ownerUserID: operation.ownerUserID,
                clientOperationID: operation.operation.id
            )
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
        return .succeeded
    }

    private nonisolated static func isPermanentEligibilityFailure(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("you must answer this daily question")
            || description.contains("daily question thread requires both partners")
            || description.contains("daily question instance was not found")
    }
}

struct SendDailyQuestionThreadMessagePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .sendThreadMessage

    private let gateway: any SupabaseDailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching

    init(
        gateway: any SupabaseDailyQuestionChatGateway,
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

        let response = try await gateway.sendMessage(
            threadID: threadID,
            body: payload.body,
            operation: operation.operation
        )
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
        return .succeeded
    }
}
