import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
func waitForMain(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

final class ChatPushTransport: LiveQueryTransport, @unchecked Sendable {
    private let open = LockedBox<AsyncThrowingStream<Data, any Error>.Continuation?>(nil)
    let openedPaths = LockedBox<[String]>([])

    func updates(path: String, args _: [String: String]) -> AsyncThrowingStream<Data, any Error> {
        openedPaths.mutate { $0.append(path) }
        return AsyncThrowingStream { continuation in
            open.mutate { $0 = continuation }
        }
    }

    func push(_ json: String) async {
        _ = await waitUntil { open.value != nil }
        open.value?.yield(Data(json.utf8))
    }
}

@MainActor
final class ChatTestOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    let clientID = UUID()

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            clientID: clientID,
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

actor ChatVoiceUploader {
    let assetID: UUID
    private(set) var uploadedParentIDs: [UUID] = []
    private(set) var uploadedPurposes: [DailyAnswerMediaPurpose] = []

    init(assetID: UUID) {
        self.assetID = assetID
    }

    func uploadMedia(
        _ media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) throws -> UUID {
        uploadedParentIDs.append(answerID)
        uploadedPurposes.append(media.purpose)
        return assetID
    }
}

extension ChatVoiceUploader: DailyAnswerMediaUploading {}

@MainActor
final class ChatTestFixture {
    let ownerUserID: UUID
    let partnerUserID: UUID
    let threadID = UUID()
    let messageID = UUID()
    let question: DailyChallengeQuestion
    let gateway: ChatTestGateway
    let cache = InMemoryDailyQuestionChatCache()
    let pendingStore = InMemoryPendingSyncOperationRepository()
    let operationProvider = ChatTestOperationProvider()

    init(question: DailyChallengeQuestion? = nil) {
        ownerUserID = question?.ownAnswerDetail?.answerUserID ?? UUID()
        partnerUserID = question?.partnerAnswerDetail?.answerUserID ?? UUID()
        self.question = question ?? makeChatQuestion(
            ownerUserID: ownerUserID,
            partnerUserID: partnerUserID
        )
        gateway = ChatTestGateway(threadID: threadID, messageID: messageID)
    }

    var summary: DailyQuestionThreadSummary {
        DailyQuestionThreadSummary(
            threadID: threadID,
            coupleID: question.coupleID,
            questionID: question.questionID,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            lastMessageID: messageID,
            lastMessageAt: Date(timeIntervalSince1970: 2),
            lastMessageSenderUserID: ownerUserID,
            lastMessageBody: "One message"
        )
    }

    func remoteMessage(body: String) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            questionID: question.questionID,
            senderUserID: ownerUserID,
            body: body,
            createdAt: Date(timeIntervalSince1970: 2),
            clientOperationID: nil,
            isSending: false
        )
    }

    func makeService() -> DailyQuestionChatService {
        DailyQuestionChatService(
            gateway: gateway,
            cache: cache,
            pendingOperationStore: pendingStore
        )
    }

    func makeViewModel(
        focusesNewest: Bool = false,
        service: (any DailyQuestionChatServicing)? = nil
    ) -> DailyQuestionChatViewModel {
        DailyQuestionChatViewModel(
            question: question,
            participants: DailyChallengeParticipants(
                currentUserID: ownerUserID,
                currentDisplayName: "You",
                partnerUserID: partnerUserID,
                partnerDisplayName: "Partner"
            ),
            focusesNewest: focusesNewest,
            service: service ?? makeService(),
            operationProvider: operationProvider
        )
    }

    /// A message that was saved on this phone and then rejected by the server.
    func cacheFailedMessage(_ body: String) async -> SyncClientOperation {
        let operation = operationProvider.makeOperation()
        await cache.append(
            DailyQuestionChatMessage(
                id: operation.id,
                threadID: nil,
                questionID: question.questionID,
                senderUserID: ownerUserID,
                body: body,
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: ownerUserID
        )
        await cache.markFailed(ownerUserID: ownerUserID, clientOperationID: operation.id)
        return operation
    }
}

extension ChatTestFixture {
    func partnerMessage(body: String, id: UUID = UUID(), at seconds: Double = 5) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: id,
            threadID: threadID,
            questionID: question.questionID,
            senderUserID: partnerUserID,
            body: body,
            createdAt: Date(timeIntervalSince1970: seconds),
            clientOperationID: nil,
            isSending: false
        )
    }

    /// The server's copy of a message this user sent.
    func ownServerCopy(body: String, at seconds: Double) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            questionID: question.questionID,
            senderUserID: ownerUserID,
            body: body,
            createdAt: Date(timeIntervalSince1970: seconds),
            clientOperationID: nil,
            isSending: false
        )
    }

    /// What the phone has saved for this chat.
    func cachedMessages() async -> [DailyQuestionChatMessage] {
        await cache.messages(ownerUserID: ownerUserID, questionID: question.questionID)
    }

    /// The messages the service shows as still on their way.
    func pendingMessages(_ service: DailyQuestionChatService) async -> [DailyQuestionChatMessage] {
        await service.pendingMessages(
            ownerUserID: ownerUserID,
            coupleID: question.coupleID,
            questionID: question.questionID
        )
    }

    func queuedOperations(_ kind: SyncPendingOperationKind) async throws -> [PendingSyncOperationSnapshot] {
        try await pendingStore.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }

    /// Records the server's answer to a queued message in the cache.
    func confirm(_ operation: SyncClientOperation, body: String) async {
        await cache.confirm(
            ownerUserID: ownerUserID,
            questionID: question.questionID,
            coupleID: question.coupleID,
            clientOperationID: operation.id,
            threadID: threadID,
            messageID: messageID,
            body: body,
            senderUserID: ownerUserID,
            createdAt: operation.localCreatedAt
        )
    }
}

extension ChatTestFixture {
    /// Saves the message of a queued send in the cache, like the app does when it queues one.
    func appendSending(
        _ operation: SyncClientOperation,
        body: String,
        threadID: UUID? = nil,
        questionID: UUID? = nil
    ) async {
        await cache.append(
            DailyQuestionChatMessage(
                id: operation.id,
                threadID: threadID,
                questionID: questionID ?? question.questionID,
                senderUserID: ownerUserID,
                body: body,
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: ownerUserID
        )
    }

    func createPayload(body: String) -> CreateDailyChatThreadPayload {
        CreateDailyChatThreadPayload(
            questionID: question.questionID,
            coupleID: question.coupleID,
            body: body
        )
    }

    func sendPayload(
        body: String,
        threadID: UUID?,
        questionID: UUID? = nil
    ) -> SendDailyChatMessagePayload {
        SendDailyChatMessagePayload(
            questionID: questionID ?? question.questionID,
            coupleID: question.coupleID,
            threadID: threadID,
            body: body
        )
    }

    func createSnapshot(_ operation: SyncClientOperation, body: String) throws -> PendingSyncOperationSnapshot {
        chatPendingSnapshot(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .createDailyQuestionThreadWithMessage,
            payload: try JSONEncoder().encode(createPayload(body: body))
        )
    }

    func sendSnapshot(
        _ operation: SyncClientOperation,
        body: String,
        threadID: UUID?
    ) throws -> PendingSyncOperationSnapshot {
        chatPendingSnapshot(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .sendThreadMessage,
            payload: try JSONEncoder().encode(sendPayload(body: body, threadID: threadID))
        )
    }

    func createHandler() -> CreateDailyChatThreadOperationHandler {
        CreateDailyChatThreadOperationHandler(gateway: gateway, cache: cache)
    }

    func sendHandler() -> SendDailyChatMessageOperationHandler {
        SendDailyChatMessageOperationHandler(gateway: gateway, cache: cache)
    }
}

/// Counts `.dailyChat` changes posted for one user.
final class ChatChangeRecorder: @unchecked Sendable {
    let count = LockedBox(0)
    private var task: Task<Void, Never>?

    init(ownerUserID: UUID) {
        // The stream starts watching when it is created, so no later post is missed.
        let changes = LocalStoreChanges.changes(in: .dailyChat)
        let count = self.count
        task = Task {
            for await change in changes where change.ownerUserID == ownerUserID {
                count.mutate { $0 += 1 }
            }
        }
    }

    func stop() {
        task?.cancel()
    }
}

enum ChatTestError: Error {
    case requested
}

func chatPendingSnapshot(
    ownerUserID: UUID,
    operation: SyncClientOperation,
    kind: SyncPendingOperationKind,
    payload: Data
) -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: ownerUserID,
        operation: operation,
        operationKind: kind,
        idempotencyScope: "chat",
        requestHash: nil,
        requestData: payload,
        status: .queued,
        attemptCount: 0,
        lastAttemptAt: nil,
        nextRetryAt: nil,
        lastError: nil,
        completedAt: nil
    )
}

func chatSyncContext(
    ownerUserID: UUID,
    pendingStore: any PendingSyncOperationPersisting = InMemoryPendingSyncOperationRepository()
) -> SyncContext {
    SyncContext(
        session: SyncSession(userID: ownerUserID),
        reason: .localChange,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: pendingStore
    )
}

func makeChatQuestion(
    ownerUserID: UUID = UUID(),
    partnerUserID: UUID = UUID(),
    revealed: Bool = true
) -> DailyChallengeQuestion {
    let ownAnswerID = UUID()
    let partnerAnswerID = UUID()
    return DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: UUID(),
        coupleID: UUID(),
        localDate: "2026-08-04",
        effectiveLocalDate: "2026-08-04",
        startsAt: Date(timeIntervalSince1970: 1),
        endsAt: Date(timeIntervalSince1970: 2),
        seededForUserID: ownerUserID,
        slotNumber: 1,
        status: .answered,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "chat.test",
        prompt: "What made you smile today?",
        shortPrompt: "A smile today",
        answerKinds: [.text],
        ownAnswer: DailyQuestionAnswerSummary(id: ownAnswerID, answeredAt: .now),
        partnerAnswer: DailyQuestionAnswerSummary(id: partnerAnswerID, answeredAt: .now),
        canViewPartnerAnswer: revealed,
        ownAnswerDetail: chatAnswerDetail(userID: ownerUserID, answerID: ownAnswerID, isOwn: true, visible: true),
        partnerAnswerDetail: chatAnswerDetail(
            userID: partnerUserID,
            answerID: partnerAnswerID,
            isOwn: false,
            visible: revealed
        ),
        origin: .own,
        isCurrentDay: true
    )
}

private func chatAnswerDetail(userID: UUID, answerID: UUID, isOwn: Bool, visible: Bool) -> DailyQuestionAnswerDetail {
    DailyQuestionAnswerDetail(
        answerUserID: userID,
        answerID: answerID,
        answeredAt: .now,
        isOwnAnswer: isOwn,
        canViewAnswer: visible,
        textBody: visible ? (isOwn ? "A good morning." : "Your message.") : nil,
        selectedUserID: nil,
        mediaAssetIDs: []
    )
}
