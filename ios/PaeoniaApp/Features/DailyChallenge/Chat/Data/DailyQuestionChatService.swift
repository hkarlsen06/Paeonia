import Foundation

protocol DailyQuestionChatServicing: Actor {
    func cachedThreadSummaries(ownerUserID: UUID) async -> [DailyQuestionThreadSummary]
    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [DailyQuestionThreadSummary]
    func cachedMessages(ownerUserID: UUID, questionID: UUID) async -> [DailyQuestionChatMessage]
    func refreshMessages(
        ownerUserID: UUID,
        questionID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage]
    /// Loads the page of messages before the oldest one this phone has, and keeps it.
    /// Returns whether older messages remain.
    func loadOlderMessages(ownerUserID: UUID, questionID: UUID, threadID: UUID) async throws -> Bool
    /// The question's rounds as last saved on this phone, nil before the first read.
    func cachedRounds(ownerUserID: UUID, questionID: UUID) async -> DailyQuestionChatRoundsRow?
    /// Reads the question's rounds from the server and keeps them on this phone.
    func refreshRounds(ownerUserID: UUID, coupleID: UUID, questionID: UUID) async throws -> DailyQuestionChatRoundsRow?
    /// Follows the question's rounds while the caller iterates. Each result is saved on
    /// this phone before the stream yields, so the caller re-reads the saved copy.
    nonisolated func liveRoundUpdates(ownerUserID: UUID, coupleID: UUID, questionID: UUID) -> AsyncStream<Void>
    /// Follows one thread's messages while the caller iterates. Each result is
    /// merged into the chat cache before the stream yields, so the caller re-reads
    /// the cache. The stream ends when the caller's task is cancelled.
    nonisolated func liveMessageUpdates(ownerUserID: UUID, questionID: UUID, threadID: UUID) -> AsyncStream<Void>
    /// When the user last saw each thread on this phone, keyed by thread id.
    func chatReadMarks(ownerUserID: UUID) async -> [UUID: Date]
    /// Records that the user has seen the thread up to `date`, and tells the
    /// unread badges to update when that moved the mark forward.
    func markThreadRead(ownerUserID: UUID, threadID: UUID, through date: Date) async
    /// Questions whose page the user has opened since the partner's answer showed up,
    /// on this phone.
    func seenPartnerAnswers(ownerUserID: UUID) async -> Set<UUID>
    /// Records that the user has seen the partner's answer, and tells the cards to
    /// update when that is new.
    func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) async
    /// The messages still sending in one couple's chat about a question. A message queued in an
    /// earlier relationship never shows in a later one.
    func pendingMessages(ownerUserID: UUID, coupleID: UUID, questionID: UUID) async -> [DailyQuestionChatMessage]
    func hasPendingThreadCreation(ownerUserID: UUID, coupleID: UUID, questionID: UUID) async -> Bool
    /// Removes a message that failed to send, so the retry replaces it.
    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async
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
    ) async throws -> DailyQuestionChatMessage
    /// Queues a voice message. The recording travels in the queued operation, so it
    /// still sends after the app closes or the phone goes offline.
    func queueVoiceMessage( // swiftlint:disable:this function_parameter_count
        ownerUserID: UUID,
        coupleID: UUID,
        questionID: UUID,
        threadID: UUID?,
        voice: DailyQuestionChatVoicePayload,
        createThread: Bool,
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage
    /// Replaces the text of the user's own message. The live message query brings the
    /// change to both phones. Throws `DailyQuestionChatEditWindowClosedError` once the
    /// server says the five minutes are over.
    func editMessage(messageID: UUID, body: String) async throws
    /// Tells the partner's phone this person is typing in the chat, or has stopped.
    func setTyping(coupleID: UUID, questionID: UUID, isTyping: Bool) async
    /// Tells the server this person has read the thread up to `messageID`, for read receipts.
    func markThreadReadOnServer(threadID: UUID, messageID: UUID) async
    /// Tells the server this person has seen the partner's answer, so it stops showing
    /// as new on their other devices and the partner sees it was read. Returns whether
    /// the server took it.
    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID: UUID) async -> Bool
    /// Follows the partner's typing and read state while the caller iterates.
    nonisolated func livePresence(coupleID: UUID, questionID: UUID) -> AsyncStream<DailyChatPresence>
}

/// The partner's typing and read state in one question's chat.
nonisolated struct DailyChatPresence: Equatable, Sendable {
    var partnerIsTyping = false
    var partnerLastReadMessageID: UUID?

    static let none = DailyChatPresence()
}

extension DailyQuestionChatServicing {
    func loadOlderMessages(ownerUserID _: UUID, questionID _: UUID, threadID _: UUID) -> Bool { false }
    func cachedRounds(ownerUserID _: UUID, questionID _: UUID) -> DailyQuestionChatRoundsRow? { nil }
    func refreshRounds(
        ownerUserID _: UUID,
        coupleID _: UUID,
        questionID _: UUID
    ) throws -> DailyQuestionChatRoundsRow? { nil }
    nonisolated func liveRoundUpdates(ownerUserID _: UUID, coupleID _: UUID, questionID _: UUID) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func editMessage(messageID _: UUID, body _: String) throws {
        throw DailyQuestionChatServiceError.unavailable
    }

    func setTyping(coupleID _: UUID, questionID _: UUID, isTyping _: Bool) {}
    func markThreadReadOnServer(threadID _: UUID, messageID _: UUID) {}
    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID _: UUID) -> Bool { true }
    nonisolated func livePresence(coupleID _: UUID, questionID _: UUID) -> AsyncStream<DailyChatPresence> {
        AsyncStream { $0.finish() }
    }

    // swiftlint:disable:next function_parameter_count
    func queueVoiceMessage(
        ownerUserID _: UUID,
        coupleID _: UUID,
        questionID _: UUID,
        threadID _: UUID?,
        voice _: DailyQuestionChatVoicePayload,
        createThread _: Bool,
        replyToMessageID _: UUID?,
        operation _: SyncClientOperation
    ) throws -> DailyQuestionChatMessage { throw DailyQuestionChatServiceError.unavailable }

    func chatReadMarks(ownerUserID _: UUID) -> [UUID: Date] { [:] }
    func markThreadRead(ownerUserID _: UUID, threadID _: UUID, through _: Date) {}
    func seenPartnerAnswers(ownerUserID _: UUID) -> Set<UUID> { [] }
    func markPartnerAnswerSeen(ownerUserID _: UUID, instanceID _: UUID) {}

    /// Services without a live connection (previews, scenarios) have nothing to follow.
    nonisolated func liveMessageUpdates(
        ownerUserID _: UUID,
        questionID _: UUID,
        threadID _: UUID
    ) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

actor DailyQuestionChatService: DailyQuestionChatServicing {
    private let gateway: any DailyQuestionChatGateway
    let cache: any DailyQuestionChatCaching
    let pendingOperationStore: any PendingSyncOperationPersisting
    let encoder = JSONEncoder()

    init(
        gateway: any DailyQuestionChatGateway,
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
        // Read before the request, so a purge that runs while it is in flight
        // makes the save a no-op.
        let generation = await cache.purgeGeneration()
        let summaries = try await gateway.loadThreadSummaries()
        guard await cache.saveSummaries(
            summaries,
            ownerUserID: ownerUserID,
            unlessPurgedSince: generation
        ) else { return [] }
        return summaries
    }

    func cachedMessages(ownerUserID: UUID, questionID: UUID) async -> [DailyQuestionChatMessage] {
        await cache.messages(ownerUserID: ownerUserID, questionID: questionID)
    }

    func refreshMessages(
        ownerUserID: UUID,
        questionID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage] {
        let generation = await cache.purgeGeneration()
        let page = try await gateway.loadMessages(threadID: threadID, questionID: questionID, before: nil)
        let cached = await cache.messages(ownerUserID: ownerUserID, questionID: questionID)
        let pending = await loadPendingMessages(ownerUserID: ownerUserID, coupleID: nil, questionID: questionID)
        // Live results can land while the request is in flight. The cache merge keeps
        // the ones this read is too old to contain.
        await cache.mergeMessages(
            DailyQuestionChatMessage.keepingOlderCached(
                page,
                remote: DailyQuestionChatMessage.claimingPending(
                    remote: page.messages,
                    cached: cached,
                    pending: pending
                ),
                cached: cached
            ),
            ownerUserID: ownerUserID,
            questionID: questionID,
            unlessPurgedSince: generation
        )
        return await cache.messages(ownerUserID: ownerUserID, questionID: questionID)
    }

    func loadOlderMessages(ownerUserID: UUID, questionID: UUID, threadID: UUID) async throws -> Bool {
        let generation = await cache.purgeGeneration()
        let cached = await cache.messages(ownerUserID: ownerUserID, questionID: questionID)
        guard let oldest = cached
            .filter({ !$0.isSending && !$0.sendFailed })
            .min(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) })
        else { return false }
        let page = try await gateway.loadMessages(
            threadID: threadID,
            questionID: questionID,
            before: DailyQuestionChatMessageCursor(createdAt: oldest.createdAt, messageID: oldest.id)
        )
        await cache.mergeOlderMessages(
            page.messages,
            ownerUserID: ownerUserID,
            questionID: questionID,
            unlessPurgedSince: generation
        )
        // A page of only removed messages would repeat the same request, so it ends the list.
        return page.hasMore && !page.messages.isEmpty
    }

    func cachedRounds(ownerUserID: UUID, questionID: UUID) async -> DailyQuestionChatRoundsRow? {
        await cache.rounds(ownerUserID: ownerUserID, questionID: questionID)
    }

    func refreshRounds(
        ownerUserID: UUID,
        coupleID: UUID,
        questionID: UUID
    ) async throws -> DailyQuestionChatRoundsRow? {
        let generation = await cache.purgeGeneration()
        let rounds = try await gateway.loadRounds(coupleID: coupleID, questionID: questionID)
        await cache.saveRounds(rounds, ownerUserID: ownerUserID, questionID: questionID, unlessPurgedSince: generation)
        return rounds
    }

    nonisolated func liveRoundUpdates(ownerUserID: UUID, coupleID: UUID, questionID: UUID) -> AsyncStream<Void> {
        let results = gateway.liveRounds(coupleID: coupleID, questionID: questionID)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                // Read before the first result, so a purge that starts while this
                // writer is suspended makes every later save a no-op.
                let generation = await cache.purgeGeneration()
                for await rounds in results {
                    guard !Task.isCancelled else { break }
                    guard await cache.saveRounds(
                        rounds,
                        ownerUserID: ownerUserID,
                        questionID: questionID,
                        unlessPurgedSince: generation
                    ) else { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated func liveMessageUpdates(
        ownerUserID: UUID,
        questionID: UUID,
        threadID: UUID
    ) -> AsyncStream<Void> {
        let results = gateway.liveMessages(threadID: threadID, questionID: questionID)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                // Read before the first result, so a purge that starts while this
                // writer is suspended makes every later save a no-op.
                let generation = await cache.purgeGeneration()
                for await page in results {
                    guard !Task.isCancelled else { break }
                    guard await saveLiveMessages(
                        page,
                        ownerUserID: ownerUserID,
                        questionID: questionID,
                        purgeGeneration: generation
                    ) else { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func saveLiveMessages(
        _ page: DailyQuestionChatMessagePage,
        ownerUserID: UUID,
        questionID: UUID,
        purgeGeneration: Int
    ) async -> Bool {
        let cached = await cache.messages(ownerUserID: ownerUserID, questionID: questionID)
        let pending = await loadPendingMessages(ownerUserID: ownerUserID, coupleID: nil, questionID: questionID)
        // The screen's task is cancelled on sign-out and account switch, but nothing
        // waits for this writer. Stop here, and let the cache refuse the save if a
        // purge ran since the subscription started.
        guard !Task.isCancelled else { return false }
        return await cache.saveMessages(
            DailyQuestionChatMessage.keepingOlderCached(
                page,
                remote: DailyQuestionChatMessage.claimingPending(
                    remote: page.messages,
                    cached: cached,
                    pending: pending
                ),
                cached: cached
            ),
            ownerUserID: ownerUserID,
            questionID: questionID,
            unlessPurgedSince: purgeGeneration
        )
    }

    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async {
        await cache.discardFailed(ownerUserID: ownerUserID, clientOperationID: clientOperationID)
    }

    func chatReadMarks(ownerUserID: UUID) async -> [UUID: Date] {
        await cache.readMarks(ownerUserID: ownerUserID)
    }

    // An edit is not queued. It only makes sense within minutes of sending, so a
    // failure leaves the text in the message box for the person to try again.
    func editMessage(messageID: UUID, body: String) async throws {
        do {
            try await gateway.editMessage(messageID: messageID, body: body)
        } catch {
            if String(describing: error).contains("messages can only be edited for 5 minutes") {
                throw DailyQuestionChatEditWindowClosedError()
            }
            throw error
        }
    }

    // Typing and read receipts are live hints, so a failed call is dropped rather than
    // queued. The next keystroke or the next message tries again.
    func setTyping(coupleID: UUID, questionID: UUID, isTyping: Bool) async {
        try? await gateway.setTyping(coupleID: coupleID, questionID: questionID, isTyping: isTyping)
    }

    func markThreadReadOnServer(threadID: UUID, messageID: UUID) async {
        try? await gateway.markThreadRead(threadID: threadID, messageID: messageID)
    }

    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID: UUID) async -> Bool {
        (try? await gateway.markAnswerSeen(instanceID: instanceID)) != nil
    }

    nonisolated func livePresence(coupleID: UUID, questionID: UUID) -> AsyncStream<DailyChatPresence> {
        gateway.livePresence(coupleID: coupleID, questionID: questionID)
    }

    func markThreadRead(ownerUserID: UUID, threadID: UUID, through date: Date) async {
        guard await cache.markRead(ownerUserID: ownerUserID, threadID: threadID, through: date) else { return }
        LocalStoreChanges.post(.dailyChat, ownerUserID: ownerUserID)
    }

    func seenPartnerAnswers(ownerUserID: UUID) async -> Set<UUID> {
        await cache.seenPartnerAnswers(ownerUserID: ownerUserID)
    }

    func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) async {
        guard await cache.markPartnerAnswerSeen(ownerUserID: ownerUserID, instanceID: instanceID) else { return }
        LocalStoreChanges.post(.dailyChat, ownerUserID: ownerUserID)
    }

}

/// The server refused an edit because the message is older than five minutes.
nonisolated struct DailyQuestionChatEditWindowClosedError: Error, Equatable, Sendable {}

nonisolated enum DailyQuestionChatServiceError: Error, Equatable, Sendable {
    case unavailable
    case missingResponse
    case missingThread
}
