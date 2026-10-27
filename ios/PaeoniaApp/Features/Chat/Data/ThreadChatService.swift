import Foundation

protocol ThreadChatServicing: Actor {
    func keepGameResult(_ result: GameConversationResult, ownerUserID: UUID, source: GameConversationSource) async
    nonisolated func liveGameUpdates(ownerUserID: UUID, coupleID: UUID, source: GameConversationSource) -> AsyncStream<
        Void
    >
    func cachedGameResult(ownerUserID: UUID, source: GameConversationSource) async -> GameConversationResult?
    func refreshGameResult(ownerUserID: UUID, coupleID: UUID, source: GameConversationSource) async throws
        -> GameConversationResult?
    func cachedThreadSummaries(ownerUserID: UUID) async -> [ThreadChatSummary]
    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [ThreadChatSummary]
    func cachedMessages(ownerUserID: UUID, subjectID: UUID) async -> [ThreadChatMessage]
    func refreshMessages(
        ownerUserID: UUID,
        subjectID: UUID,
        threadID: UUID
    ) async throws -> [ThreadChatMessage]
    /// Loads the page of messages before the oldest one this phone has, and keeps it.
    /// Returns whether older messages remain.
    func loadOlderMessages(ownerUserID: UUID, subjectID: UUID, threadID: UUID) async throws -> Bool
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
    nonisolated func liveMessageUpdates(ownerUserID: UUID, subjectID: UUID, threadID: UUID) -> AsyncStream<Void>
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
    func pendingMessages(ownerUserID: UUID, coupleID: UUID, subjectID: UUID) async -> [ThreadChatMessage]
    func hasPendingThreadCreation(ownerUserID: UUID, coupleID: UUID, subjectID: UUID) async -> Bool
    /// Removes a message that failed to send, so the retry replaces it.
    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async
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
    ) async throws -> ThreadChatMessage
    /// Queues a voice message. The recording travels in the queued operation, so it
    /// still sends after the app closes or the phone goes offline.
    func queueVoiceMessage( // swiftlint:disable:this function_parameter_count
        ownerUserID: UUID,
        coupleID: UUID,
        subject: ThreadChatSubject,
        threadID: UUID?,
        voice: ThreadChatVoicePayload,
        createThread: Bool,
        replyTo: ThreadChatItemID?,
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessage
    /// Replaces the text of the user's own message. The live message query brings the
    /// change to both phones. Throws `ThreadChatEditWindowClosedError` once the
    /// server says the five minutes are over.
    func editMessage(messageID: UUID, body: String) async throws
    /// Takes back the user's own message for both people. A message the server has is
    /// shown as deleted at once, and the delete waits in the send queue when the phone is
    /// offline. A message still sending or failed is dropped from this phone instead, and
    /// never goes out. Throws `ThreadChatServiceError.stillSending` while the
    /// message is on its way to the server and can't be stopped.
    func deleteMessage(
        ownerUserID: UUID,
        message: ThreadChatMessage,
        operation: SyncClientOperation
    ) async throws
    /// The partner took a message back and this phone heard it in a silent push. The cached
    /// chat shows the message as deleted, with no text, and its files leave this phone.
    func applyRemoteDeletion(ownerUserID: UUID, messageID: UUID) async
    /// Sets the user's emoji reaction to a message or an answer, or takes it back with nil,
    /// then reads the messages or the question's days again so this phone has it.
    /// `threadID` is the chat's thread, which a message always has.
    func setReaction( // swiftlint:disable:this function_parameter_count
        ownerUserID: UUID,
        coupleID: UUID,
        subjectID: UUID,
        threadID: UUID?,
        item: ThreadChatItemID,
        emoji: String?
    ) async throws
    /// Tells the partner's phone this person is typing in the chat, or has stopped.
    func setTyping(coupleID: UUID, subject: ThreadChatSubject, isTyping: Bool) async
    /// Tells the server this person has read the thread up to `messageID`, for read receipts.
    func markThreadReadOnServer(threadID: UUID, messageID: UUID) async
    /// Tells the server this person has seen the partner's answer, so it stops showing
    /// as new on their other devices and the partner sees it was read. Returns whether
    /// the server took it.
    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID: UUID) async -> Bool
    /// Follows the partner's typing and read state while the caller iterates.
    nonisolated func livePresence(coupleID: UUID, subject: ThreadChatSubject) -> AsyncStream<ThreadChatPresence>
}

/// The partner's typing and read state in one chat.
nonisolated struct ThreadChatPresence: Equatable, Sendable {
    var partnerIsTyping = false
    var partnerLastReadMessageID: UUID?

    static let none = ThreadChatPresence()
}

extension ThreadChatServicing {
    func keepGameResult(_: GameConversationResult, ownerUserID _: UUID, source _: GameConversationSource) {}
    nonisolated func liveGameUpdates(ownerUserID _: UUID, coupleID _: UUID, source _: GameConversationSource)
        -> AsyncStream<Void>
    {
        AsyncStream { $0.finish() }
    }
    func cachedGameResult(ownerUserID _: UUID, source _: GameConversationSource) -> GameConversationResult? { nil }
    func refreshGameResult(ownerUserID _: UUID, coupleID _: UUID, source _: GameConversationSource) throws
        -> GameConversationResult?
    {
        throw ThreadChatServiceError.unavailable
    }

    func loadOlderMessages(ownerUserID _: UUID, subjectID _: UUID, threadID _: UUID) -> Bool { false }
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
        throw ThreadChatServiceError.unavailable
    }

    func applyRemoteDeletion(ownerUserID _: UUID, messageID _: UUID) {}

    func deleteMessage(
        ownerUserID _: UUID,
        message _: ThreadChatMessage,
        operation _: SyncClientOperation
    ) throws {
        throw ThreadChatServiceError.unavailable
    }

    // swiftlint:disable:next function_parameter_count
    func setReaction(
        ownerUserID _: UUID,
        coupleID _: UUID,
        subjectID _: UUID,
        threadID _: UUID?,
        item _: ThreadChatItemID,
        emoji _: String?
    ) throws {
        throw ThreadChatServiceError.unavailable
    }

    func setTyping(coupleID _: UUID, subject _: ThreadChatSubject, isTyping _: Bool) {}
    func markThreadReadOnServer(threadID _: UUID, messageID _: UUID) {}
    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID _: UUID) -> Bool { true }
    nonisolated func livePresence(coupleID _: UUID, subject _: ThreadChatSubject) -> AsyncStream<ThreadChatPresence> {
        AsyncStream { $0.finish() }
    }

    // swiftlint:disable:next function_parameter_count
    func queueVoiceMessage(
        ownerUserID _: UUID,
        coupleID _: UUID,
        subject _: ThreadChatSubject,
        threadID _: UUID?,
        voice _: ThreadChatVoicePayload,
        createThread _: Bool,
        replyTo _: ThreadChatItemID?,
        operation _: SyncClientOperation
    ) throws -> ThreadChatMessage { throw ThreadChatServiceError.unavailable }

    func chatReadMarks(ownerUserID _: UUID) -> [UUID: Date] { [:] }
    func markThreadRead(ownerUserID _: UUID, threadID _: UUID, through _: Date) {}
    func seenPartnerAnswers(ownerUserID _: UUID) -> Set<UUID> { [] }
    func markPartnerAnswerSeen(ownerUserID _: UUID, instanceID _: UUID) {}

    /// Services without a live connection (previews, scenarios) have nothing to follow.
    nonisolated func liveMessageUpdates(
        ownerUserID _: UUID,
        subjectID _: UUID,
        threadID _: UUID
    ) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

actor ThreadChatService: ThreadChatServicing {
    let gateway: any ThreadChatGateway
    let cache: any ThreadChatCaching
    let pendingOperationStore: any PendingSyncOperationPersisting
    /// Removes the files of deleted photos and voice messages from this phone.
    let mediaCache: (any DailyAnswerMediaCacheEvicting)?
    let encoder = JSONEncoder()

    init(
        gateway: any ThreadChatGateway,
        cache: any ThreadChatCaching,
        pendingOperationStore: any PendingSyncOperationPersisting,
        mediaCache: (any DailyAnswerMediaCacheEvicting)? = nil
    ) {
        self.gateway = gateway
        self.cache = cache
        self.pendingOperationStore = pendingOperationStore
        self.mediaCache = mediaCache
    }

    func cachedThreadSummaries(ownerUserID: UUID) async -> [ThreadChatSummary] {
        await cache.summaries(ownerUserID: ownerUserID)
    }

    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [ThreadChatSummary] {
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

    func cachedMessages(ownerUserID: UUID, subjectID: UUID) async -> [ThreadChatMessage] {
        await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
    }

    func refreshMessages(
        ownerUserID: UUID,
        subjectID: UUID,
        threadID: UUID
    ) async throws -> [ThreadChatMessage] {
        let newest = try await refreshNewestMessages(ownerUserID: ownerUserID, subjectID: subjectID, threadID: threadID)
        await revalidateOlderCachedMessages(
            ownerUserID: ownerUserID,
            subjectID: subjectID,
            threadID: threadID,
            newestPage: newest.page,
            purgeGeneration: newest.purgeGeneration
        )
        return await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
    }

    /// Reads the newest page and merges it into the cache. Older cached messages stay as
    /// they were, so a caller that opens the chat follows up with
    /// `revalidateOlderCachedMessages`.
    func refreshNewestMessages(
        ownerUserID: UUID,
        subjectID: UUID,
        threadID: UUID
    ) async throws -> (page: ThreadChatMessagePage, purgeGeneration: Int) {
        let generation = await cache.purgeGeneration()
        let page = try await gateway.loadMessages(threadID: threadID, subjectID: subjectID, before: nil)
        let cached = await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
        let pending = await loadPendingMessages(ownerUserID: ownerUserID, coupleID: nil, subjectID: subjectID)
        let remote = await withDeletions(
            ThreadChatMessage.claimingPending(remote: page.messages, cached: cached, pending: pending),
            cached: cached,
            ownerUserID: ownerUserID
        )
        // Live results can land while the request is in flight. The cache merge keeps
        // the ones this read is too old to contain.
        await cache.mergeMessages(
            ThreadChatMessage.keepingOlderCached(page, remote: remote, cached: cached),
            ownerUserID: ownerUserID,
            subjectID: subjectID,
            unlessPurgedSince: generation
        )
        return (page, generation)
    }

    func loadOlderMessages(ownerUserID: UUID, subjectID: UUID, threadID: UUID) async throws -> Bool {
        let generation = await cache.purgeGeneration()
        let cached = await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
        guard let oldest = cached
            .filter({ !$0.isSending && !$0.sendFailed })
            .min(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) })
        else { return false }
        let page = try await gateway.loadMessages(
            threadID: threadID,
            subjectID: subjectID,
            before: ThreadChatMessageCursor(createdAt: oldest.createdAt, messageID: oldest.id)
        )
        await cache.mergeOlderMessages(
            await withDeletions(page.messages, cached: cached, ownerUserID: ownerUserID),
            ownerUserID: ownerUserID,
            subjectID: subjectID,
            unlessPurgedSince: generation
        )
        // A page of only removed messages would repeat the same request, so it ends the list.
        return page.hasMore && !page.messages.isEmpty
    }

    func cachedRounds(ownerUserID: UUID, questionID: UUID) async -> DailyQuestionChatRoundsRow? {
        await cache.rounds(ownerUserID: ownerUserID, subjectID: questionID)
    }

    func refreshRounds(
        ownerUserID: UUID,
        coupleID: UUID,
        questionID: UUID
    ) async throws -> DailyQuestionChatRoundsRow? {
        let generation = await cache.purgeGeneration()
        let rounds = try await gateway.loadRounds(coupleID: coupleID, questionID: questionID)
        await cache.saveRounds(rounds, ownerUserID: ownerUserID, subjectID: questionID, unlessPurgedSince: generation)
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
                        subjectID: questionID,
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
        subjectID: UUID,
        threadID: UUID
    ) -> AsyncStream<Void> {
        let results = gateway.liveMessages(threadID: threadID, subjectID: subjectID)
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
                        subjectID: subjectID,
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
        _ page: ThreadChatMessagePage,
        ownerUserID: UUID,
        subjectID: UUID,
        purgeGeneration: Int
    ) async -> Bool {
        let cached = await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
        let pending = await loadPendingMessages(ownerUserID: ownerUserID, coupleID: nil, subjectID: subjectID)
        let remote = await withDeletions(
            ThreadChatMessage.claimingPending(remote: page.messages, cached: cached, pending: pending),
            cached: cached,
            ownerUserID: ownerUserID
        )
        // The screen's task is cancelled on sign-out and account switch, but nothing
        // waits for this writer. Stop here, and let the cache refuse the save if a
        // purge ran since the subscription started.
        guard !Task.isCancelled else { return false }
        return await cache.saveMessages(
            ThreadChatMessage.keepingOlderCached(page, remote: remote, cached: cached),
            ownerUserID: ownerUserID,
            subjectID: subjectID,
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
                throw ThreadChatEditWindowClosedError()
            }
            throw error
        }
    }

    // A reaction is not queued either. A failure puts the earlier reaction back on screen
    // and says so, and the live query brings the change to both phones.
    // swiftlint:disable:next function_parameter_count
    func setReaction(
        ownerUserID: UUID,
        coupleID: UUID,
        subjectID: UUID,
        threadID: UUID?,
        item: ThreadChatItemID,
        emoji: String?
    ) async throws {
        try await gateway.setReaction(on: item, emoji: emoji)
        switch item {
        case .message:
            guard let threadID else { return }
            _ = try? await refreshNewestMessages(ownerUserID: ownerUserID, subjectID: subjectID, threadID: threadID)
        case .answer:
            _ = try? await refreshRounds(ownerUserID: ownerUserID, coupleID: coupleID, questionID: subjectID)
        }
    }

    // Typing and read receipts are live hints, so a failed call is dropped rather than
    // queued. The next keystroke or the next message tries again.
    func setTyping(coupleID: UUID, subject: ThreadChatSubject, isTyping: Bool) async {
        try? await gateway.setTyping(coupleID: coupleID, subject: subject, isTyping: isTyping)
    }

    func markThreadReadOnServer(threadID: UUID, messageID: UUID) async {
        try? await gateway.markThreadRead(threadID: threadID, messageID: messageID)
    }

    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID: UUID) async -> Bool {
        (try? await gateway.markAnswerSeen(instanceID: instanceID)) != nil
    }

    nonisolated func livePresence(coupleID: UUID, subject: ThreadChatSubject) -> AsyncStream<ThreadChatPresence> {
        gateway.livePresence(coupleID: coupleID, subject: subject)
    }

    func markThreadRead(ownerUserID: UUID, threadID: UUID, through date: Date) async {
        guard await cache.markRead(ownerUserID: ownerUserID, threadID: threadID, through: date) else { return }
        LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
    }

    func seenPartnerAnswers(ownerUserID: UUID) async -> Set<UUID> {
        await cache.seenPartnerAnswers(ownerUserID: ownerUserID)
    }

    func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) async {
        guard await cache.markPartnerAnswerSeen(ownerUserID: ownerUserID, instanceID: instanceID) else { return }
        LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
    }

}

/// The server refused an edit because the message is older than five minutes.
nonisolated struct ThreadChatEditWindowClosedError: Error, Equatable, Sendable {}

nonisolated enum ThreadChatServiceError: Error, Equatable, Sendable {
    case unavailable
    /// The message is on its way to the server, so it can't be taken back yet.
    case stillSending
    case missingResponse
    case missingThread
}
