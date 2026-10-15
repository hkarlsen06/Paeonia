import Foundation

nonisolated enum DailyQuestionChatServiceFactory {
    static func makeDefault() -> any DailyQuestionChatServicing {
        let pendingStore: any PendingSyncOperationPersisting
        if let localStore = PaeoniaLocalStore.shared {
            pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        } else {
            pendingStore = InMemoryPendingSyncOperationRepository()
        }

        let gateway: any DailyQuestionChatGateway
        if let client = try? PaeoniaConvexClientProvider.shared.client() {
            gateway = LiveDailyQuestionChatGateway(client: client)
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
    func cachedThreadSummaries(ownerUserID _: UUID) -> [DailyQuestionThreadSummary] { [] }
    func refreshThreadSummaries(ownerUserID _: UUID) throws -> [DailyQuestionThreadSummary] { [] }
    func cachedMessages(ownerUserID _: UUID, questionID _: UUID) -> [DailyQuestionChatMessage] { [] }
    func refreshMessages(
        ownerUserID _: UUID,
        questionID _: UUID,
        threadID _: UUID
    ) throws -> [DailyQuestionChatMessage] { [] }
    func pendingMessages(ownerUserID _: UUID, coupleID _: UUID, questionID _: UUID) -> [DailyQuestionChatMessage] { [] }
    func hasPendingThreadCreation(ownerUserID _: UUID, coupleID _: UUID, questionID _: UUID) -> Bool { false }
    func discardFailedMessage(ownerUserID _: UUID, clientOperationID _: UUID) {}
    // swiftlint:disable:next function_parameter_count
    func queueMessage(
        ownerUserID _: UUID,
        coupleID _: UUID,
        questionID _: UUID,
        threadID _: UUID?,
        body _: String,
        photos _: DailyQuestionChatPhotosPayload?,
        createThread _: Bool,
        replyToMessageID _: UUID?,
        operation _: SyncClientOperation
    ) throws -> DailyQuestionChatMessage { throw DailyQuestionChatServiceError.unavailable }
}

private actor UnavailableDailyQuestionChatGateway: DailyQuestionChatGateway {
    func loadThreadSummaries() throws -> [DailyQuestionThreadSummary] {
        throw DailyQuestionChatServiceError.unavailable
    }

    func loadMessages(
        threadID _: UUID,
        questionID _: UUID,
        before _: DailyQuestionChatMessageCursor?
    ) throws -> DailyQuestionChatMessagePage {
        throw DailyQuestionChatServiceError.unavailable
    }

    func createThreadWithMessage(
        _: CreateDailyChatThreadPayload,
        mediaAssetIDs _: [UUID],
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse { throw DailyQuestionChatServiceError.unavailable }
    func sendMessage(
        threadID _: UUID,
        body _: String,
        mediaAssetIDs _: [UUID],
        replyToMessageID _: UUID?,
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse { throw DailyQuestionChatServiceError.unavailable }
}
