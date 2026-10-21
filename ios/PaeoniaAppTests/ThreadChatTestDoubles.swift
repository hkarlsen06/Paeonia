import Foundation
import Testing
@testable import PaeoniaApp

/// Wraps the real service and pauses one `hasPendingThreadCreation` call after it has
/// read, so a test can finish a newer read first and then let this older one return.
actor PausingChatService: ThreadChatServicing {
    private let base: ThreadChatService
    private var pausesNextRead = false
    private var pausedRead: CheckedContinuation<Void, Never>?

    init(base: ThreadChatService) {
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

    func hasPendingThreadCreation(ownerUserID: UUID, coupleID: UUID, subjectID: UUID) async -> Bool {
        let result = await base.hasPendingThreadCreation(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            subjectID: subjectID
        )
        if pausesNextRead {
            pausesNextRead = false
            await withCheckedContinuation { pausedRead = $0 }
        }
        return result
    }

    func cachedThreadSummaries(ownerUserID: UUID) async -> [ThreadChatSummary] {
        await base.cachedThreadSummaries(ownerUserID: ownerUserID)
    }

    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [ThreadChatSummary] {
        try await base.refreshThreadSummaries(ownerUserID: ownerUserID)
    }

    func cachedMessages(ownerUserID: UUID, subjectID: UUID) async -> [ThreadChatMessage] {
        await base.cachedMessages(ownerUserID: ownerUserID, subjectID: subjectID)
    }

    func refreshMessages(
        ownerUserID: UUID,
        subjectID: UUID,
        threadID: UUID
    ) async throws -> [ThreadChatMessage] {
        try await base.refreshMessages(ownerUserID: ownerUserID, subjectID: subjectID, threadID: threadID)
    }

    func pendingMessages(ownerUserID: UUID, coupleID: UUID, subjectID: UUID) async -> [ThreadChatMessage] {
        await base.pendingMessages(ownerUserID: ownerUserID, coupleID: coupleID, subjectID: subjectID)
    }

    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async {
        await base.discardFailedMessage(ownerUserID: ownerUserID, clientOperationID: clientOperationID)
    }

    // swiftlint:disable:next function_parameter_count
    func queueMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        subject: ThreadChatSubject,
        threadID: UUID?,
        body: String,
        photos: ThreadChatPhotosPayload?,
        createThread: Bool,
        replyTo: ThreadChatItemID?,
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessage {
        try await base.queueMessage(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            subject: subject,
            threadID: threadID,
            body: body,
            photos: photos,
            createThread: createThread,
            replyTo: replyTo,
            operation: operation
        )
    }
}

/// Stands in for the messages subscription. Tests push the full message list, like
/// the server pushing a new query result.
final class LiveMessageSource: @unchecked Sendable {
    private let open = LockedBox<AsyncStream<ThreadChatMessagePage>.Continuation?>(nil)
    let subscriptionCount = LockedBox(0)

    func stream() -> AsyncStream<ThreadChatMessagePage> {
        subscriptionCount.mutate { $0 += 1 }
        return AsyncStream { continuation in
            open.mutate { $0 = continuation }
        }
    }

    /// Pushes the whole thread, as when it fits in the newest page.
    func push(_ messages: [ThreadChatMessage]) async {
        await push(
            ThreadChatMessagePage(messages: messages, hasMore: false, oldestAt: messages.first?.createdAt)
        )
    }

    func push(_ page: ThreadChatMessagePage) async {
        _ = await waitUntil { open.value != nil }
        open.value?.yield(page)
    }
}

actor ChatTestGateway: ThreadChatGateway {
    nonisolated let liveSource = LiveMessageSource()
    private let threadID: UUID
    private let messageID: UUID
    private var summaries: [ThreadChatSummary] = []
    private var messages: [ThreadChatMessage] = []
    /// What each load asked for, newest first, so a test can check the cursor.
    private(set) var loadCursors: [ThreadChatMessageCursor?] = []
    private var olderPages: [ThreadChatMessagePage] = []
    private var newestPageHasMore = false
    private var shouldFail = false
    private var sendError: (any Error)?
    private var holdsLoads = false
    private var heldLoads = [CheckedContinuation<Void, Never>]()
    private(set) var loadCallCount = 0
    private(set) var createCallCount = 0
    private(set) var sendCallCount = 0
    private(set) var lastMediaAssetIDs: [UUID]?
    private(set) var lastReplyTo: ThreadChatItemID?
    private(set) var answerSeenCallCount = 0
    private var answerSeenFails = false
    private(set) var lastEdit: (messageID: UUID, body: String)?
    private var editError: (any Error)?
    private(set) var deletedMessageIDs: [UUID] = []
    private var deleteError: (any Error)?
    private var roundsRow: DailyQuestionChatRoundsRow?

    init(threadID: UUID, messageID: UUID) {
        self.threadID = threadID
        self.messageID = messageID
    }

    func setRemote(
        summaries: [ThreadChatSummary],
        messages: [ThreadChatMessage]
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
        guard let roundsRow else { throw ThreadChatServiceError.unavailable }
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

    func setDeleteError(_ error: (any Error)?) {
        deleteError = error
    }

    func deleteMessage(messageID: UUID, operation _: SyncClientOperation) throws {
        if let deleteError { throw deleteError }
        deletedMessageIDs.append(messageID)
    }

    func markAnswerSeen(instanceID _: UUID) throws {
        answerSeenCallCount += 1
        if answerSeenFails { throw ThreadChatServiceError.unavailable }
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

    func loadThreadSummaries() async throws -> [ThreadChatSummary] {
        loadCallCount += 1
        let result = summaries
        await waitWhileHeld()
        if shouldFail { throw ChatTestError.requested }
        return result
    }

    func setPageHasMore(_ hasMore: Bool) {
        newestPageHasMore = hasMore
    }

    /// The pages the next loads with a cursor return, in order.
    func setOlderPages(_ pages: [ThreadChatMessagePage]) {
        olderPages = pages
    }

    private func nextOlderPage() -> ThreadChatMessagePage {
        olderPages.isEmpty ? ThreadChatMessagePage(messages: [], hasMore: false) : olderPages.removeFirst()
    }

    func loadMessages(
        threadID _: UUID,
        subjectID _: UUID,
        before: ThreadChatMessageCursor?
    ) async throws -> ThreadChatMessagePage {
        loadCallCount += 1
        loadCursors.append(before)
        let result = before == nil
            ? ThreadChatMessagePage(
                messages: messages, hasMore: newestPageHasMore, oldestAt: messages.first?.createdAt
            )
            : nextOlderPage()
        await waitWhileHeld()
        if shouldFail { throw ChatTestError.requested }
        return result
    }

    private func waitWhileHeld() async {
        guard holdsLoads else { return }
        await withCheckedContinuation { heldLoads.append($0) }
    }

    nonisolated func liveMessages(threadID _: UUID, subjectID _: UUID) -> AsyncStream<ThreadChatMessagePage> {
        liveSource.stream()
    }

    func createThreadWithMessage(
        _: CreateChatThreadPayload,
        mediaAssetIDs: [UUID],
        operation _: SyncClientOperation
    ) throws -> ThreadChatMessageResponse {
        createCallCount += 1
        lastMediaAssetIDs = mediaAssetIDs
        if let sendError { throw sendError }
        if shouldFail { throw ChatTestError.requested }
        return ThreadChatMessageResponse(threadID: threadID, messageID: messageID)
    }

    func sendMessage(
        threadID _: UUID,
        body _: String,
        mediaAssetIDs: [UUID],
        replyTo: ThreadChatItemID?,
        operation _: SyncClientOperation
    ) throws -> ThreadChatMessageResponse {
        sendCallCount += 1
        lastMediaAssetIDs = mediaAssetIDs
        lastReplyTo = replyTo
        if let sendError { throw sendError }
        if shouldFail { throw ChatTestError.requested }
        return ThreadChatMessageResponse(threadID: threadID, messageID: messageID)
    }
}
