import Foundation
import Observation

@MainActor
@Observable
final class DailyQuestionChatViewModel {
    enum Notice: Equatable {
        case loadFailed
        /// The message could not be saved on this phone. It stays in the message field.
        case sendFailed
        /// The message was saved but the server turned it down. It stays in the list, marked as failed.
        case deliveryFailed
        case messageTooLong
        case unavailable
    }

    static let maximumMessageLength = 4_000

    let question: DailyChallengeQuestion
    private let service: any DailyQuestionChatServicing
    private let operationProvider: any SyncClientOperationProviding
    private var syncAfterLocalChange: (@MainActor () async -> Void)?
    private(set) var participants: DailyChallengeParticipants
    private(set) var messages: [DailyQuestionChatMessage] = []
    private(set) var threadID: UUID?
    private(set) var isLoading = true
    private(set) var notice: Notice?
    private var hasQueuedThreadCreation = false
    private var isQueueing = false
    /// Counts reads of the store. A read that finishes after a newer one started
    /// holds older data, so it must not replace what the newer read showed.
    private var readGeneration = 0
    /// Failed messages the screen has already shown. `nil` until the first read, so
    /// a failure from an earlier visit shows its red icon but raises no banner.
    private var seenFailedOperationIDs: Set<UUID>?

    init(
        question: DailyChallengeQuestion,
        participants: DailyChallengeParticipants,
        service: (any DailyQuestionChatServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        syncAfterLocalChange: (@MainActor () async -> Void)? = nil
    ) {
        self.question = question
        self.participants = participants
        self.service = service ?? DailyQuestionChatServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.syncAfterLocalChange = syncAfterLocalChange
    }

    var isChatAvailable: Bool {
        question.isChatAvailable && participants.currentUserID != nil
    }

    var hasSendingMessages: Bool {
        messages.contains(where: \.isSending)
    }

    func refreshParticipants(_ participants: DailyChallengeParticipants) {
        self.participants = participants
    }

    func load() async {
        defer { isLoading = false }
        guard let ownerUserID = participants.currentUserID, question.isChatAvailable else {
            notice = .unavailable
            return
        }

        await readStore(ownerUserID: ownerUserID)

        do {
            let summaries = try await service.refreshThreadSummaries(ownerUserID: ownerUserID)
            threadID = summaries.first(where: { $0.instanceID == question.id })?.threadID ?? threadID
            if let threadID {
                _ = try await service.refreshMessages(
                    ownerUserID: ownerUserID,
                    instanceID: question.id,
                    threadID: threadID
                )
                await readStore(ownerUserID: ownerUserID)
            }
        } catch {
            // Without a thread there is nothing missing, and the composer still works.
            // Only a thread that exists but cannot be read is a load error.
            if !isCancellation(error), threadID != nil, messages.isEmpty {
                notice = .loadFailed
            }
        }
    }

    /// Re-reads the thread, the cached messages, and the messages still sending.
    private func readStore(ownerUserID: UUID) async {
        readGeneration += 1
        let generation = readGeneration
        let cachedSummaries = await service.cachedThreadSummaries(ownerUserID: ownerUserID)
        // The thread never goes back to nil, so a late read may still set it.
        threadID = cachedSummaries.first(where: { $0.instanceID == question.id })?.threadID ?? threadID
        let cached = await service.cachedMessages(ownerUserID: ownerUserID, instanceID: question.id)
        let pending = await service.pendingMessages(ownerUserID: ownerUserID, instanceID: question.id)
        let isCreatingThread = await service.hasPendingThreadCreation(
            ownerUserID: ownerUserID,
            instanceID: question.id
        )
        guard generation == readGeneration else { return }
        hasQueuedThreadCreation = isCreatingThread
        messages = DailyQuestionChatMessage.visibleOrdered(remote: cached, optimistic: pending)
        raiseNoticeForNewFailures()
    }

    private func raiseNoticeForNewFailures() {
        let failed = Set(messages.filter(\.sendFailed).compactMap(\.clientOperationID))
        if let seen = seenFailedOperationIDs, !failed.isSubset(of: seen) {
            notice = .deliveryFailed
        }
        seenFailedOperationIDs = (seenFailedOperationIDs ?? []).union(failed)
    }

    /// Keeps the chat current while the screen is open, until the calling task is
    /// cancelled. Messages that arrive from the partner, and a thread the partner
    /// starts, show up without a reload. The live results are written to the chat
    /// cache first, so reopening the chat offline shows the same messages.
    func observeLiveUpdates() async {
        guard let ownerUserID = participants.currentUserID, question.isChatAvailable else { return }

        var followedThreadID: UUID?
        var messageUpdates: Task<Void, Never>?
        defer { messageUpdates?.cancel() }

        let changes = LocalStoreChanges.changes(in: .dailyChat)
        // Check once before waiting, in case the thread arrived before this started.
        var shouldRead = true
        var iterator = changes.makeAsyncIterator()
        while shouldRead {
            await readStore(ownerUserID: ownerUserID)
            if let threadID, threadID != followedThreadID {
                followedThreadID = threadID
                messageUpdates?.cancel()
                let instanceID = question.id
                messageUpdates = Task { @MainActor [weak self, service] in
                    let updates = service.liveMessageUpdates(
                        ownerUserID: ownerUserID,
                        instanceID: instanceID,
                        threadID: threadID
                    )
                    for await _ in updates {
                        guard let self else { return }
                        await self.readStore(ownerUserID: ownerUserID)
                    }
                }
            }
            // Wait for the next change to this user's chats. Other users' changes are skipped.
            shouldRead = false
            while let change = await iterator.next() {
                if change.ownerUserID == ownerUserID {
                    shouldRead = true
                    break
                }
            }
        }
    }

    /// Queues a message. `failedOperationID` is the operation of a failed message the
    /// person tapped to send again. The new message replaces it.
    func send(_ text: String, replacingFailed failedOperationID: UUID? = nil) async -> Bool {
        guard let ownerUserID = participants.currentUserID, question.isChatAvailable else {
            notice = .unavailable
            return false
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        // The server counts code points, so one emoji made of several counts as several.
        guard body.unicodeScalars.count <= Self.maximumMessageLength else {
            notice = .messageTooLong
            return false
        }
        // A second tap while the first message is still being saved would send it twice.
        guard !isQueueing else { return false }
        isQueueing = true
        defer { isQueueing = false }

        let createThread = threadID == nil && !hasQueuedThreadCreation
        do {
            _ = try await service.queueMessage(
                ownerUserID: ownerUserID,
                coupleID: question.coupleID,
                instanceID: question.id,
                threadID: threadID,
                body: body,
                createThread: createThread,
                operation: operationProvider.makeOperation()
            )
            if createThread { hasQueuedThreadCreation = true }
            // Remove the failed copy only after the retry is saved, so a failed save loses nothing.
            if let failedOperationID {
                await service.discardFailedMessage(ownerUserID: ownerUserID, clientOperationID: failedOperationID)
            }
            PaeoniaHaptics.selection()
            await readStore(ownerUserID: ownerUserID)
            syncInBackground()
            return true
        } catch {
            notice = .sendFailed
            return false
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func syncInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await syncAfterLocalChange?()
            // The send confirmation lands in the cache. A full reload here could
            // overwrite a newer live result with an older server read.
            guard let ownerUserID = participants.currentUserID else { return }
            await readStore(ownerUserID: ownerUserID)
        }
    }

    private nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

extension DailyQuestionChatViewModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .loadFailed: .dailyChatErrorLoadTitle
        case .sendFailed: .dailyChatErrorSendTitle
        case .deliveryFailed: .dailyChatErrorDeliveryTitle
        case .messageTooLong: .dailyChatErrorTooLongTitle
        case .unavailable: .dailyChatErrorUnavailableTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .loadFailed: .dailyChatErrorLoadMessage
        case .sendFailed: .dailyChatErrorSendMessage
        case .deliveryFailed: .dailyChatErrorDeliveryMessage
        case .messageTooLong: .dailyChatErrorTooLongMessage
        case .unavailable: .dailyChatErrorUnavailableMessage
        }
    }
}
