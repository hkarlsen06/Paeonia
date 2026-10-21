import Foundation

nonisolated enum ThreadChatServiceFactory {
    static func makeDefault() -> any ThreadChatServicing {
        let pendingStore: any PendingSyncOperationPersisting
        if let localStore = PaeoniaLocalStore.shared {
            pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        } else {
            pendingStore = InMemoryPendingSyncOperationRepository()
        }

        let gateway: any ThreadChatGateway
        if let client = try? PaeoniaConvexClientProvider.shared.client() {
            gateway = LiveThreadChatGateway(client: client)
        } else {
            gateway = UnavailableThreadChatGateway()
        }
        return ThreadChatService(
            gateway: gateway,
            cache: FileThreadChatCache.shared,
            pendingOperationStore: pendingStore,
            mediaCache: DailyAnswerMediaImageService.shared
        )
    }
}

actor EmptyThreadChatService: ThreadChatServicing {
    func cachedThreadSummaries(ownerUserID _: UUID) -> [ThreadChatSummary] { [] }
    func refreshThreadSummaries(ownerUserID _: UUID) throws -> [ThreadChatSummary] { [] }
    func cachedMessages(ownerUserID _: UUID, subjectID _: UUID) -> [ThreadChatMessage] { [] }
    func refreshMessages(
        ownerUserID _: UUID,
        subjectID _: UUID,
        threadID _: UUID
    ) throws -> [ThreadChatMessage] { [] }
    func pendingMessages(ownerUserID _: UUID, coupleID _: UUID, subjectID _: UUID) -> [ThreadChatMessage] { [] }
    func hasPendingThreadCreation(ownerUserID _: UUID, coupleID _: UUID, subjectID _: UUID) -> Bool { false }
    func discardFailedMessage(ownerUserID _: UUID, clientOperationID _: UUID) {}
    // swiftlint:disable:next function_parameter_count
    func queueMessage(
        ownerUserID _: UUID,
        coupleID _: UUID,
        subject _: ThreadChatSubject,
        threadID _: UUID?,
        body _: String,
        photos _: ThreadChatPhotosPayload?,
        createThread _: Bool,
        replyTo _: ThreadChatItemID?,
        operation _: SyncClientOperation
    ) throws -> ThreadChatMessage { throw ThreadChatServiceError.unavailable }
}

private actor UnavailableThreadChatGateway: ThreadChatGateway {
    func loadThreadSummaries() throws -> [ThreadChatSummary] {
        throw ThreadChatServiceError.unavailable
    }

    func loadMessages(
        threadID _: UUID,
        subjectID _: UUID,
        before _: ThreadChatMessageCursor?
    ) throws -> ThreadChatMessagePage {
        throw ThreadChatServiceError.unavailable
    }

    func createThreadWithMessage(
        _: CreateChatThreadPayload,
        mediaAssetIDs _: [UUID],
        operation _: SyncClientOperation
    ) throws -> ThreadChatMessageResponse { throw ThreadChatServiceError.unavailable }
    func sendMessage(
        threadID _: UUID,
        body _: String,
        mediaAssetIDs _: [UUID],
        replyTo _: ThreadChatItemID?,
        operation _: SyncClientOperation
    ) throws -> ThreadChatMessageResponse { throw ThreadChatServiceError.unavailable }
}
