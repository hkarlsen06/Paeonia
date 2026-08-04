import Foundation
import Supabase

protocol DailyQuestionChatServicing: Actor {
    func cachedThreadSummaries(ownerUserID: UUID) async -> [DailyQuestionThreadSummary]
    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [DailyQuestionThreadSummary]
    func cachedMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage]
    func refreshMessages(
        ownerUserID: UUID,
        instanceID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage]
    func pendingMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage]
    func hasPendingThreadCreation(ownerUserID: UUID, instanceID: UUID) async -> Bool
    func queueMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        instanceID: UUID,
        threadID: UUID?,
        body: String,
        createThread: Bool,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage
}

protocol SupabaseDailyQuestionChatGateway: Actor {
    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary]
    func loadMessages(threadID: UUID, instanceID: UUID) async throws -> [DailyQuestionChatMessage]
    func createThreadWithMessage(
        _ payload: CreateDailyQuestionThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse
    func sendMessage(
        threadID: UUID,
        body: String,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse
}

actor DailyQuestionChatService: DailyQuestionChatServicing {
    private let gateway: any SupabaseDailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let encoder = JSONEncoder()

    init(
        gateway: any SupabaseDailyQuestionChatGateway,
        cache: any DailyQuestionChatCaching,
        pendingOperationStore: any PendingSyncOperationPersisting
    ) {
        self.gateway = gateway
        self.cache = cache
        self.pendingOperationStore = pendingOperationStore
    }

    func cachedThreadSummaries(ownerUserID: UUID) async -> [DailyQuestionThreadSummary] {
        await cache.summaries(ownerUserID: ownerUserID)
    }

    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [DailyQuestionThreadSummary] {
        let summaries = try await gateway.loadThreadSummaries()
        await cache.saveSummaries(summaries, ownerUserID: ownerUserID)
        return summaries
    }

    func cachedMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage] {
        await cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
    }

    func refreshMessages(
        ownerUserID: UUID,
        instanceID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage] {
        let messages = try await gateway.loadMessages(threadID: threadID, instanceID: instanceID)
        await cache.saveMessages(messages, ownerUserID: ownerUserID, instanceID: instanceID)
        return await cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
    }

    func pendingMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage] {
        async let creates = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        async let sends = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .sendThreadMessage
        )

        let createMessages = (try? await creates) ?? []
        let sendMessages = (try? await sends) ?? []
        return (createMessages + sendMessages).compactMap { pendingMessage($0, instanceID: instanceID) }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func hasPendingThreadCreation(ownerUserID: UUID, instanceID: UUID) async -> Bool {
        let operations = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )) ?? []
        return operations.contains { operation in
            guard let data = operation.requestData,
                  let payload = try? JSONDecoder().decode(
                    CreateDailyQuestionThreadMessageOperationPayload.self,
                    from: data
                  ) else { return false }
            return payload.instanceID == instanceID
        }
    }

    func queueMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        instanceID: UUID,
        threadID: UUID?,
        body: String,
        createThread: Bool,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage {
        let requestData: Data
        let operationKind: SyncPendingOperationKind
        if createThread {
            operationKind = .createDailyQuestionThreadWithMessage
            requestData = try encoder.encode(
                CreateDailyQuestionThreadMessageOperationPayload(
                    instanceID: instanceID,
                    coupleID: coupleID,
                    body: body
                )
            )
        } else {
            operationKind = .sendThreadMessage
            requestData = try encoder.encode(
                SendDailyQuestionThreadMessageOperationPayload(
                    instanceID: instanceID,
                    coupleID: coupleID,
                    threadID: threadID,
                    body: body
                )
            )
        }

        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: operationKind,
                idempotencyScope: "daily-question-chat:\(instanceID.uuidString.lowercased())",
                requestData: requestData
            )
        )

        let message = DailyQuestionChatMessage(
            id: operation.id,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: ownerUserID,
            body: body,
            createdAt: operation.localCreatedAt,
            clientOperationID: operation.id,
            isSending: true
        )
        await cache.append(message, ownerUserID: ownerUserID)
        return message
    }

    private func pendingMessage(
        _ operation: PendingSyncOperationSnapshot,
        instanceID: UUID
    ) -> DailyQuestionChatMessage? {
        guard let data = operation.requestData else { return nil }

        let body: String
        let messageThreadID: UUID?
        switch operation.operationKind {
        case .createDailyQuestionThreadWithMessage:
            guard let payload = try? JSONDecoder().decode(
                CreateDailyQuestionThreadMessageOperationPayload.self,
                from: data
            ), payload.instanceID == instanceID else { return nil }
            body = payload.body
            messageThreadID = nil
        case .sendThreadMessage:
            guard let payload = try? JSONDecoder().decode(
                SendDailyQuestionThreadMessageOperationPayload.self,
                from: data
            ), payload.instanceID == instanceID else { return nil }
            body = payload.body
            messageThreadID = payload.threadID
        default:
            return nil
        }

        return DailyQuestionChatMessage(
            id: operation.operation.id,
            threadID: messageThreadID,
            instanceID: instanceID,
            senderUserID: operation.ownerUserID,
            body: body,
            createdAt: operation.operation.localCreatedAt,
            clientOperationID: operation.operation.id,
            isSending: true
        )
    }
}

actor LiveSupabaseDailyQuestionChatGateway: SupabaseDailyQuestionChatGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary] {
        let rows: [ConversationThreadRow] = try await client
            .rpc("get_conversation_threads")
            .execute()
            .value
        return rows.compactMap(\.dailyQuestionSummary)
    }

    func loadMessages(threadID: UUID, instanceID: UUID) async throws -> [DailyQuestionChatMessage] {
        let rows: [ThreadMessageRow] = try await client
            .rpc("get_thread_messages", params: ThreadMessagesRequest(threadID: threadID))
            .execute()
            .value
        return rows.compactMap { $0.message(instanceID: instanceID) }
    }

    func createThreadWithMessage(
        _ payload: CreateDailyQuestionThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse {
        _ = try await client.auth.session
        let rows: [DailyQuestionThreadMessageResponse] = try await client
            .rpc(
                "create_daily_question_thread_with_message",
                params: CreateThreadMessageRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
        guard let response = rows.first else { throw DailyQuestionChatServiceError.missingResponse }
        return response
    }

    func sendMessage(
        threadID: UUID,
        body: String,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse {
        _ = try await client.auth.session
        let rows: [DailyQuestionThreadMessageResponse] = try await client
            .rpc(
                "send_thread_message",
                params: SendThreadMessageRequest(
                    threadID: threadID,
                    body: body,
                    operation: operation
                )
            )
            .execute()
            .value
        guard let response = rows.first else { throw DailyQuestionChatServiceError.missingResponse }
        return response
    }
}

nonisolated enum DailyQuestionChatServiceError: Error, Equatable, Sendable {
    case unavailable
    case missingResponse
    case missingThread
}

nonisolated enum DailyQuestionChatServiceFactory {
    static func makeDefault() -> any DailyQuestionChatServicing {
        let pendingStore: any PendingSyncOperationPersisting
        if let localStore = PaeoniaLocalStore.shared {
            pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        } else {
            pendingStore = InMemoryPendingSyncOperationRepository()
        }

        let gateway: any SupabaseDailyQuestionChatGateway
        if let client = try? PaeoniaSupabaseClientProvider.shared.client() {
            gateway = LiveSupabaseDailyQuestionChatGateway(client: client)
        } else {
            gateway = UnavailableDailyQuestionChatGateway()
        }
        return DailyQuestionChatService(
            gateway: gateway,
            cache: FileDailyQuestionChatCache.shared,
            pendingOperationStore: pendingStore
        )
    }
}

actor EmptyDailyQuestionChatService: DailyQuestionChatServicing {
    func cachedThreadSummaries(ownerUserID _: UUID) async -> [DailyQuestionThreadSummary] { [] }
    func refreshThreadSummaries(ownerUserID _: UUID) async throws -> [DailyQuestionThreadSummary] { [] }
    func cachedMessages(ownerUserID _: UUID, instanceID _: UUID) async -> [DailyQuestionChatMessage] { [] }
    func refreshMessages(
        ownerUserID _: UUID,
        instanceID _: UUID,
        threadID _: UUID
    ) async throws -> [DailyQuestionChatMessage] { [] }
    func pendingMessages(ownerUserID _: UUID, instanceID _: UUID) async -> [DailyQuestionChatMessage] { [] }
    func hasPendingThreadCreation(ownerUserID _: UUID, instanceID _: UUID) async -> Bool { false }
    func queueMessage(
        ownerUserID _: UUID,
        coupleID _: UUID,
        instanceID _: UUID,
        threadID _: UUID?,
        body _: String,
        createThread _: Bool,
        operation _: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage { throw DailyQuestionChatServiceError.unavailable }
}

private actor UnavailableDailyQuestionChatGateway: SupabaseDailyQuestionChatGateway {
    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary] { throw DailyQuestionChatServiceError.unavailable }
    func loadMessages(threadID _: UUID, instanceID _: UUID) async throws -> [DailyQuestionChatMessage] { throw DailyQuestionChatServiceError.unavailable }
    func createThreadWithMessage(
        _: CreateDailyQuestionThreadMessageOperationPayload,
        operation _: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse { throw DailyQuestionChatServiceError.unavailable }
    func sendMessage(
        threadID _: UUID,
        body _: String,
        operation _: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse { throw DailyQuestionChatServiceError.unavailable }
}

nonisolated private struct ConversationThreadRow: Decodable {
    let threadID: UUID
    let coupleID: UUID
    let kind: String
    let dailyQuestionInstanceID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let moderationStatus: String
    let lastMessageID: UUID?
    let lastMessageAt: Date?
    let lastMessageSenderUserID: UUID?
    let lastMessageDeletedAt: Date?
    let lastMessageModerationStatus: String?
    let lastMessageBody: String?

    var dailyQuestionSummary: DailyQuestionThreadSummary? {
        guard kind == "daily_question", deletedAt == nil, moderationStatus == "visible",
              let dailyQuestionInstanceID else { return nil }
        let previewIsVisible = lastMessageDeletedAt == nil
            && lastMessageModerationStatus == "visible"
        return DailyQuestionThreadSummary(
            threadID: threadID,
            coupleID: coupleID,
            instanceID: dailyQuestionInstanceID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageID: previewIsVisible ? lastMessageID : nil,
            lastMessageAt: previewIsVisible ? lastMessageAt : nil,
            lastMessageSenderUserID: previewIsVisible ? lastMessageSenderUserID : nil,
            lastMessageBody: previewIsVisible ? lastMessageBody : nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case coupleID = "couple_id"
        case kind
        case dailyQuestionInstanceID = "daily_question_instance_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case moderationStatus = "moderation_status"
        case lastMessageID = "last_message_id"
        case lastMessageAt = "last_message_at"
        case lastMessageSenderUserID = "last_message_sender_user_id"
        case lastMessageDeletedAt = "last_message_deleted_at"
        case lastMessageModerationStatus = "last_message_moderation_status"
        case lastMessageBody = "last_message_body"
    }
}

nonisolated private struct ThreadMessageRow: Decodable {
    let threadID: UUID
    let messageID: UUID
    let senderUserID: UUID
    let body: String?
    let createdAt: Date
    let deletedAt: Date?
    let moderationStatus: String

    func message(instanceID: UUID) -> DailyQuestionChatMessage? {
        guard deletedAt == nil, moderationStatus == "visible", let body else { return nil }
        return DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt,
            clientOperationID: nil,
            isSending: false
        )
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case messageID = "message_id"
        case senderUserID = "sender_user_id"
        case body
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case moderationStatus = "moderation_status"
    }
}

nonisolated private struct ThreadMessagesRequest: Encodable {
    let threadID: UUID
    enum CodingKeys: String, CodingKey { case threadID = "p_thread_id" }
}

nonisolated private struct CreateThreadMessageRequest: Encodable {
    let instanceID: UUID
    let body: String
    let mediaAssetIDs: [UUID] = []
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: CreateDailyQuestionThreadMessageOperationPayload, operation: SyncClientOperation) {
        instanceID = payload.instanceID
        body = payload.body
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case body = "p_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated private struct SendThreadMessageRequest: Encodable {
    let threadID: UUID
    let body: String
    let mediaAssetIDs: [UUID] = []
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(threadID: UUID, body: String, operation: SyncClientOperation) {
        self.threadID = threadID
        self.body = body
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "p_thread_id"
        case body = "p_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
