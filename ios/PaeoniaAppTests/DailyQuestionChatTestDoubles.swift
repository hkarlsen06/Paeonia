import Foundation
import Testing
@testable import PaeoniaApp

/// Wraps the real service and pauses one `hasPendingThreadCreation` call after it has
/// read, so a test can finish a newer read first and then let this older one return.
actor PausingChatService: DailyQuestionChatServicing {
    private let base: DailyQuestionChatService
    private var pausesNextRead = false
    private var pausedRead: CheckedContinuation<Void, Never>?

    init(base: DailyQuestionChatService) {
        self.base = base
    }

    var isPaused: Bool {
        pausedRead != nil
    }

    func pauseNextRead() {
        pausesNextRead = true
    }

    func resumePausedRead() {
        pausedRead?.resume()
        pausedRead = nil
    }

    func hasPendingThreadCreation(ownerUserID: UUID, coupleID: UUID, questionID: UUID) async -> Bool {
        let result = await base.hasPendingThreadCreation(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            questionID: questionID
        )
        if pausesNextRead {
            pausesNextRead = false
            await withCheckedContinuation { pausedRead = $0 }
        }
        return result
    }

    func cachedThreadSummaries(ownerUserID: UUID) async -> [DailyQuestionThreadSummary] {
        await base.cachedThreadSummaries(ownerUserID: ownerUserID)
    }

    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [DailyQuestionThreadSummary] {
        try await base.refreshThreadSummaries(ownerUserID: ownerUserID)
    }

    func cachedMessages(ownerUserID: UUID, questionID: UUID) async -> [DailyQuestionChatMessage] {
        await base.cachedMessages(ownerUserID: ownerUserID, questionID: questionID)
    }

    func refreshMessages(
        ownerUserID: UUID,
        questionID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage] {
        try await base.refreshMessages(ownerUserID: ownerUserID, questionID: questionID, threadID: threadID)
    }

    func pendingMessages(ownerUserID: UUID, coupleID: UUID, questionID: UUID) async -> [DailyQuestionChatMessage] {
        await base.pendingMessages(ownerUserID: ownerUserID, coupleID: coupleID, questionID: questionID)
    }

    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async {
        await base.discardFailedMessage(ownerUserID: ownerUserID, clientOperationID: clientOperationID)
    }

    // swiftlint:disable:next function_parameter_count
    func queueMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        questionID: UUID,
        threadID: UUID?,
        body: String,
        photos: DailyQuestionChatPhotosPayload?,
        createThread: Bool,
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage {
        try await base.queueMessage(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            questionID: questionID,
            threadID: threadID,
            body: body,
            photos: photos,
            createThread: createThread,
            replyToMessageID: replyToMessageID,
            operation: operation
        )
    }
}

/// Stands in for the messages subscription. Tests push the full message list, like
/// the server pushing a new query result.
final class LiveMessageSource: @unchecked Sendable {
    private let open = LockedBox<AsyncStream<[DailyQuestionChatMessage]>.Continuation?>(nil)
    let subscriptionCount = LockedBox(0)

    func stream() -> AsyncStream<[DailyQuestionChatMessage]> {
        subscriptionCount.mutate { $0 += 1 }
        return AsyncStream { continuation in
            open.mutate { $0 = continuation }
        }
    }

    func push(_ messages: [DailyQuestionChatMessage]) async {
        _ = await waitUntil { open.value != nil }
        open.value?.yield(messages)
    }
}

actor ChatTestGateway: DailyQuestionChatGateway {
    nonisolated let liveSource = LiveMessageSource()
    private let threadID: UUID
    private let messageID: UUID
    private var summaries: [DailyQuestionThreadSummary] = []
    private var messages: [DailyQuestionChatMessage] = []
    private var shouldFail = false
    private var sendError: (any Error)?
    private var holdsLoads = false
    private var heldLoads = [CheckedContinuation<Void, Never>]()
    private(set) var loadCallCount = 0
    private(set) var createCallCount = 0
    private(set) var sendCallCount = 0
    private(set) var lastMediaAssetIDs: [UUID]?
    private(set) var lastReplyToMessageID: UUID?
    private(set) var answerSeenCallCount = 0
    private var answerSeenFails = false
    private(set) var lastEdit: (messageID: UUID, body: String)?
    private var editError: (any Error)?
    private var roundsRow: DailyQuestionChatRoundsRow?

    init(threadID: UUID, messageID: UUID) {
        self.threadID = threadID
        self.messageID = messageID
    }

    func setRemote(
        summaries: [DailyQuestionThreadSummary],
        messages: [DailyQuestionChatMessage]
    ) {
        self.summaries = summaries
        self.messages = messages
    }

    func setFailure(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func setRounds(_ row: DailyQuestionChatRoundsRow?) {
        roundsRow = row
    }

    func loadRounds(coupleID _: UUID, questionID _: UUID) throws -> DailyQuestionChatRoundsRow {
        guard let roundsRow else { throw DailyQuestionChatServiceError.unavailable }
        return roundsRow
    }

    func setAnswerSeenFailure(_ fails: Bool) {
        answerSeenFails = fails
    }

    func setEditError(_ error: (any Error)?) {
        editError = error
    }

    func editMessage(messageID: UUID, body: String) throws {
        if let editError { throw editError }
        if shouldFail { throw ChatTestError.requested }
        lastEdit = (messageID, body)
    }

    func markAnswerSeen(instanceID _: UUID) throws {
        answerSeenCallCount += 1
        if answerSeenFails { throw DailyQuestionChatServiceError.unavailable }
    }

    /// Makes only the send calls fail, with the error a real server would produce.
    func setSendError(_ error: (any Error)?) {
        sendError = error
    }

    /// Makes loads stop after they read their result, so a test can change the
    /// cache while a request is out. The result is the data from before the stop.
    func holdLoads() {
        holdsLoads = true
    }

    func releaseLoads() {
        holdsLoads = false
        let waiting = heldLoads
        heldLoads = []
        waiting.forEach { $0.resume() }
    }

    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary] {
        loadCallCount += 1
        let result = summaries
        await waitWhileHeld()
        if shouldFail { throw ChatTestError.requested }
        return result
    }

    func loadMessages(threadID _: UUID, questionID _: UUID) async throws -> [DailyQuestionChatMessage] {
        loadCallCount += 1
        let result = messages
        await waitWhileHeld()
        if shouldFail { throw ChatTestError.requested }
        return result
    }

    private func waitWhileHeld() async {
        guard holdsLoads else { return }
        await withCheckedContinuation { heldLoads.append($0) }
    }

    nonisolated func liveMessages(threadID _: UUID, questionID _: UUID) -> AsyncStream<[DailyQuestionChatMessage]> {
        liveSource.stream()
    }

    func createThreadWithMessage(
        _: CreateDailyChatThreadPayload,
        mediaAssetIDs: [UUID],
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse {
        createCallCount += 1
        lastMediaAssetIDs = mediaAssetIDs
        if let sendError { throw sendError }
        if shouldFail { throw ChatTestError.requested }
        return DailyQuestionThreadMessageResponse(threadID: threadID, messageID: messageID)
    }

    func sendMessage(
        threadID _: UUID,
        body _: String,
        mediaAssetIDs: [UUID],
        replyToMessageID: UUID?,
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse {
        sendCallCount += 1
        lastMediaAssetIDs = mediaAssetIDs
        lastReplyToMessageID = replyToMessageID
        if let sendError { throw sendError }
        if shouldFail { throw ChatTestError.requested }
        return DailyQuestionThreadMessageResponse(threadID: threadID, messageID: messageID)
    }
}
