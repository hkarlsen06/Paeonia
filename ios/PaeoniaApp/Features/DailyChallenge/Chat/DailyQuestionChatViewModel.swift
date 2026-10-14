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
        /// A recording could not be turned into a message on this phone.
        case voiceFailed
        /// Picked photos could not be prepared or saved on this phone.
        case photoFailed
        /// A change to a sent message didn't reach the server. The text stays in the box.
        case editFailed
        /// The five minutes to change a message ran out.
        case editWindowClosed
    }

    /// How saving an edit went, so the composer knows what to do with its text.
    enum EditOutcome {
        /// Saved, or nothing changed. The composer puts back what it held before.
        case saved
        /// Not saved. The composer stays in edit mode with the text.
        case failed
        /// Too late to edit. The composer leaves edit mode and keeps the text, so it
        /// can go out as a new message.
        case windowClosed
    }

    static let maximumMessageLength = 4_000

    private(set) var question: DailyChallengeQuestion
    private let service: any DailyQuestionChatServicing
    private let operationProvider: any SyncClientOperationProviding
    private var syncAfterLocalChange: (@MainActor () async -> Void)?
    private(set) var participants: DailyChallengeParticipants
    private(set) var messages: [DailyQuestionChatMessage] = []
    private(set) var threadID: UUID?
    private(set) var isLoading = true
    /// Becomes true once the screen has read this phone's copy of the chat.
    private(set) var hasReadStore = false
    private(set) var notice: Notice?
    /// The message the next send replies to, shown above the composer.
    private(set) var replyTarget: DailyQuestionChatMessage?
    /// The user's own message whose text the composer is changing.
    private(set) var editTarget: DailyQuestionChatMessage?
    /// Changes when the composer should take focus, for example after picking a reply.
    private(set) var composerFocusRequest = 0
    /// Typing dots and read receipts.
    let presence: DailyChatPresenceModel
    /// True while the chat is on screen and the app is in front, so reading counts.
    private var isScreenActive = false
    /// The server heard during this visit that the partner's answer was seen, or is
    /// hearing it now.
    private var answerSeenUpload: AnswerSeenUpload = .notSent
    private enum AnswerSeenUpload { case notSent, sending, sent }
    private var newestPartnerMessageID: UUID?
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
        let service = service ?? DailyQuestionChatServiceFactory.makeDefault()
        self.service = service
        presence = DailyChatPresenceModel(instanceID: question.id, service: service)
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.syncAfterLocalChange = syncAfterLocalChange
    }

    var isChatAvailable: Bool {
        question.isChatAvailable && participants.currentUserID != nil
    }

    /// A message failed to send at least once. Only then does the screen say it is
    /// saved on this phone, so a normal send never flashes that line.
    var hasHeldMessages: Bool {
        messages.contains { $0.isSending && $0.isHeldOnPhone }
    }

    /// The answers that open the conversation, oldest first. The partner's shows only
    /// once it is revealed.
    var answers: [DailyQuestionAnswerDetail] {
        let partnerAnswer = question.partnerAnswerDetail.flatMap { $0.canViewAnswer ? $0 : nil }
        return [question.ownAnswerDetail, partnerAnswer]
            .compactMap(\.self)
            .sorted { $0.answeredAt < $1.answeredAt }
    }

    /// Why the chat can't start yet, shown under the answers instead of the composer.
    var waitingMessage: LocalizedStringResource? {
        guard !isChatAvailable else { return nil }
        if question.partnerAnswer == nil {
            return .dailyChatWaitingPartner(participants.partnerName)
        }
        return .dailyChallengePartnerRevealWaiting(participants.partnerName)
    }

    func refreshParticipants(_ participants: DailyChallengeParticipants) {
        self.participants = participants
    }

    /// The question changes while the screen is open, for example when the partner
    /// answers and the chat opens up.
    func refreshQuestion(_ question: DailyChallengeQuestion) {
        guard question.id == self.question.id else { return }
        self.question = question
    }

    /// Reads this phone's copy of the chat. Called before the screen opens, so its
    /// first frame already shows every message and nothing moves in after it appears.
    func prepare() async {
        guard let ownerUserID = participants.currentUserID, question.isChatAvailable else { return }
        await readStore(ownerUserID: ownerUserID)
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
        hasReadStore = true
        raiseNoticeForNewFailures()
        let newestPartner = messages.last { $0.senderUserID != ownerUserID }?.id
        if newestPartner != newestPartnerMessageID {
            if newestPartnerMessageID != nil || newestPartner != nil { presence.partnerMessageArrived() }
            newestPartnerMessageID = newestPartner
        }
        // The screen is open, so everything it shows counts as seen, the partner's
        // answer included.
        await service.markPartnerAnswerSeen(ownerUserID: ownerUserID, instanceID: question.id)
        // Notification Center can be slow to answer, so the chat doesn't wait on it.
        let shownMessageIDs = Set(messages.map(\.id))
        Task { [instanceID = question.id] in
            await DeliveredNotifications.clearQuestion(instanceID: instanceID, shownMessageIDs: shownMessageIDs)
        }
        let newestDelivered = messages.filter { !$0.isSending && !$0.sendFailed }.map(\.createdAt).max()
        if let threadID, let newestDelivered {
            await service.markThreadRead(ownerUserID: ownerUserID, threadID: threadID, through: newestDelivered)
        }
        markReadOnServerIfActive()
        markAnswerSeenOnServerIfActive()
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

        // The queue changes too, so a message that failed to send says so.
        let changes = LocalStoreChanges.changes(in: .dailyChat, .pendingOperations)
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

// MARK: - Replies, sending, typing, and reading

extension DailyQuestionChatViewModel {
    /// Only messages the server has can be replied to. A message still sending has no id there yet.
    func canReply(to message: DailyQuestionChatMessage) -> Bool {
        !message.isSending && !message.sendFailed && message.threadID != nil
    }

    func setReplyTarget(_ message: DailyQuestionChatMessage) {
        // The composer holds the edited text, so a reply waits until the edit is done.
        guard canReply(to: message), editTarget == nil else { return }
        replyTarget = message
        composerFocusRequest += 1
    }

    func cancelReply() {
        replyTarget = nil
    }

    /// The message a reply points at, when it is still in the chat.
    func message(withID id: UUID) -> DailyQuestionChatMessage? {
        messages.first { $0.id == id }
    }

    /// Queues a message. `failedOperationID` is the operation of a failed message the
    /// person tapped to send again. The new message replaces it and keeps its reply.
    func send(
        _ text: String,
        replacingFailed failedOperationID: UUID? = nil,
        replyToMessageID retriedReplyID: UUID? = nil
    ) async -> Bool {
        await send(text, photos: [], replacingFailed: failedOperationID, replyToMessageID: retriedReplyID)
    }

    private func send(
        _ text: String,
        photos: [DailyQuestionChatPhoto],
        replacingFailed failedOperationID: UUID?,
        replyToMessageID retriedReplyID: UUID?
    ) async -> Bool {
        guard let ownerUserID = participants.currentUserID, question.isChatAvailable else {
            notice = .unavailable
            return false
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !photos.isEmpty else { return false }
        // The server counts code points, so one emoji made of several counts as several.
        guard body.unicodeScalars.count <= Self.maximumMessageLength else {
            notice = .messageTooLong
            return false
        }
        // A second tap while the first message is still being saved would send it twice.
        guard !isQueueing else { return false }
        isQueueing = true
        defer { isQueueing = false }

        let replyID = failedOperationID == nil ? replyTarget?.id : retriedReplyID
        let photosPayload = photosPayload(for: photos)
        do {
            try await queue(ownerUserID: ownerUserID, replacingFailed: failedOperationID) { createThread in
                _ = try await service.queueMessage(
                    ownerUserID: ownerUserID,
                    coupleID: question.coupleID,
                    instanceID: question.id,
                    threadID: threadID,
                    body: body,
                    photos: photosPayload,
                    createThread: createThread,
                    replyToMessageID: replyID,
                    operation: operationProvider.makeOperation()
                )
            }
            if failedOperationID == nil { replyTarget = nil }
            return true
        } catch {
            notice = photos.isEmpty ? .sendFailed : .photoFailed
            return false
        }
    }

    /// The queued form of compressed photos. Every photo is reserved under one new
    /// message id, with fixed upload operations so a retry reuses them.
    private func photosPayload(for photos: [DailyQuestionChatPhoto]) -> DailyQuestionChatPhotosPayload? {
        guard !photos.isEmpty else { return nil }
        return DailyQuestionChatPhotosPayload(
            messageID: UUID(),
            items: photos.compactMap { photo in
                photo.data.map { data in
                    DailyQuestionChatPhotosPayload.Item(
                        data: data,
                        width: photo.width ?? 0,
                        height: photo.height ?? 0,
                        reserveOperation: operationProvider.makeOperation(),
                        finalizeOperation: operationProvider.makeOperation()
                    )
                }
            }
        )
    }

    /// Saves one message to the send queue, then shows it and starts sending.
    private func queue(
        ownerUserID: UUID,
        replacingFailed failedOperationID: UUID?,
        _ enqueue: (_ createThread: Bool) async throws -> Void
    ) async throws {
        let createThread = threadID == nil && !hasQueuedThreadCreation
        try await enqueue(createThread)
        if createThread { hasQueuedThreadCreation = true }
        // Remove the failed copy only after the retry is saved, so a failed save loses nothing.
        if let failedOperationID {
            await service.discardFailedMessage(ownerUserID: ownerUserID, clientOperationID: failedOperationID)
        }
        PaeoniaHaptics.selection()
        await presence.stopTyping()
        await readStore(ownerUserID: ownerUserID)
        syncInBackground()
    }

    /// The chat came on screen or left it, or the app moved to or from the front.
    func setScreenActive(_ isActive: Bool) {
        isScreenActive = isActive
        if isActive {
            markReadOnServerIfActive()
            markAnswerSeenOnServerIfActive()
        } else {
            Task { await presence.stopTyping() }
        }
    }

    func draftChanged(_ text: String) {
        // Changing a sent message is not writing a new one, so the partner sees no dots.
        guard editTarget == nil else { return }
        presence.draftChanged(text)
    }

    /// Read receipts count only what the person could see: the newest message the
    /// server has, while the chat is on screen.
    private func markReadOnServerIfActive() {
        guard isScreenActive,
              let newest = messages.last(where: { !$0.isSending && !$0.sendFailed && $0.threadID != nil }),
              let threadID = newest.threadID
        else { return }
        presence.markRead(threadID: threadID, messageID: newest.id)
    }

    /// Like the chat's read receipts, the partner's answer counts as seen only while
    /// the page is on screen. The server keeps the first time, so once a visit is
    /// enough. A failed send tries again on the next read of the chat or return to the
    /// page. Questions from today are also sent from the Questions tab.
    private func markAnswerSeenOnServerIfActive() {
        guard isScreenActive, answerSeenUpload == .notSent, question.isChatAvailable,
              question.partnerAnswerSeenAt == nil
        else { return }
        answerSeenUpload = .sending
        let instanceID = question.id
        Task {
            let sent = await service.markPartnerAnswerSeenOnServer(instanceID: instanceID)
            answerSeenUpload = sent ? .sent : .notSent
        }
    }
}

// MARK: - Photo and voice messages

extension DailyQuestionChatViewModel {
    /// Queues a message with photos from the composer, already compressed, and the
    /// text as their caption.
    func send(_ text: String, photos: [DailyQuestionChatPhoto]) async -> Bool {
        await send(text, photos: photos, replacingFailed: nil, replyToMessageID: nil)
    }

    /// Sends a failed photo message again from the compressed copies kept on this phone.
    func resendPhotos(_ message: DailyQuestionChatMessage) async {
        let photos = (message.photos ?? []).compactMap { photo -> DailyQuestionChatPhoto? in
            photo.data == nil ? nil : photo
        }
        guard message.sendFailed, !photos.isEmpty else { return }
        _ = await send(
            message.body,
            photos: photos,
            replacingFailed: message.clientOperationID,
            replyToMessageID: message.replyToMessageID
        )
    }

    /// Queues a voice message recorded with the composer's microphone button. The
    /// recording is read into the queued message and its file deleted.
    func sendVoice(fileURL: URL, durationMs: Int) async -> Bool {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let data = try? Data(contentsOf: fileURL) else {
            notice = .voiceFailed
            return false
        }
        return await sendVoice(
            data: data,
            durationMs: durationMs,
            replacingFailed: nil,
            replyToMessageID: replyTarget?.id
        )
    }

    /// Sends a voice message that failed again, from the copy kept on this phone.
    func resendVoice(_ message: DailyQuestionChatMessage) async {
        guard message.sendFailed, let data = message.voice?.data else { return }
        _ = await sendVoice(
            data: data,
            durationMs: message.voice?.durationMs ?? 0,
            replacingFailed: message.clientOperationID,
            replyToMessageID: message.replyToMessageID
        )
    }

    private func sendVoice(
        data: Data,
        durationMs: Int,
        replacingFailed failedOperationID: UUID?,
        replyToMessageID: UUID?
    ) async -> Bool {
        guard let ownerUserID = participants.currentUserID, question.isChatAvailable else {
            notice = .unavailable
            return false
        }
        guard !isQueueing else { return false }
        isQueueing = true
        defer { isQueueing = false }

        do {
            try await queue(ownerUserID: ownerUserID, replacingFailed: failedOperationID) { createThread in
                _ = try await service.queueVoiceMessage(
                    ownerUserID: ownerUserID,
                    coupleID: question.coupleID,
                    instanceID: question.id,
                    threadID: threadID,
                    voice: DailyQuestionChatVoicePayload(
                        messageID: UUID(),
                        data: data,
                        durationMs: durationMs,
                        reserveOperation: operationProvider.makeOperation(),
                        finalizeOperation: operationProvider.makeOperation()
                    ),
                    createThread: createThread,
                    replyToMessageID: replyToMessageID,
                    operation: operationProvider.makeOperation()
                )
            }
            if failedOperationID == nil { replyTarget = nil }
            return true
        } catch {
            notice = .voiceFailed
            return false
        }
    }
}

// MARK: - Editing

extension DailyQuestionChatViewModel {
    func canEdit(_ message: DailyQuestionChatMessage) -> Bool {
        message.canEdit(by: participants.currentUserID)
    }

    /// One edit at a time. Switching would throw away the changes typed so far.
    func startEditing(_ message: DailyQuestionChatMessage) {
        guard canEdit(message), editTarget == nil else { return }
        replyTarget = nil
        editTarget = message
        composerFocusRequest += 1
        Task { await presence.stopTyping() }
    }

    func cancelEdit() {
        editTarget = nil
    }

    /// Saves the new text of `editTarget`. The live message query shows the change on
    /// both phones once the server has it.
    func saveEdit(_ text: String) async -> EditOutcome {
        guard let target = editTarget else { return .saved }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .failed }
        guard body.unicodeScalars.count <= Self.maximumMessageLength else {
            notice = .messageTooLong
            return .failed
        }
        guard body != target.body else {
            editTarget = nil
            return .saved
        }
        do {
            try await service.editMessage(messageID: target.id, body: body)
            editTarget = nil
            PaeoniaHaptics.selection()
            return .saved
        } catch is DailyQuestionChatEditWindowClosedError {
            editTarget = nil
            notice = .editWindowClosed
            return .windowClosed
        } catch {
            notice = .editFailed
            return .failed
        }
    }
}
