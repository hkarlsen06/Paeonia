import Foundation
import Observation

@MainActor
@Observable
final class ThreadChatViewModel {
    enum Notice: Equatable {
        case loadFailed(PaeoniaFailure)
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
        case editFailed(PaeoniaFailure)
        /// The five minutes to change a message ran out.
        case editWindowClosed
        /// A reaction didn't reach the server. The earlier one shows again.
        case reactionFailed(PaeoniaFailure)
        /// Taking a message back could not be saved on this phone. The message stays.
        case deleteFailed
        /// The message is still on its way to the server, so it can't be taken back yet.
        case deleteWaiting
    }

    static let maximumMessageLength = 4_000

    /// What the chat is about: a question, a memory or a story.
    let subject: ThreadChatSubject
    let coupleID: UUID
    /// The card that opens a memory's or a story's chat. Nil in a question's chat, which opens
    /// with its question. `ThreadChatScreen` replaces it when a memory's note changes.
    var header: ThreadChatHeader?
    /// The day the page was opened from. The page shows every day of this question. Nil in a
    /// memory's or a story's chat, which has no days and no answers.
    private(set) var question: DailyChallengeQuestion?
    /// The days of the question as the server last sent them, oldest first. Nil until
    /// this phone has any copy of that list.
    private(set) var loadedRounds: [DailyChallengeQuestion]?
    /// The server has answered in this visit, so its list is up to date.
    var roundsAreConfirmed = false
    /// The page opens on the question's newest day instead of on `question`'s own day.
    private let focusesNewest: Bool
    /// The day the page scrolls to when it opens. Nil means the newest day.
    private var focusedInstanceID: UUID? { focusesNewest ? nil : question?.id }
    /// The partner's answer on the opened day plays its reveal when it shows, once. Set
    /// before the page reads the chat, because that read marks the answer seen.
    @ObservationIgnored var revealsPartnerAnswer = false
    let service: any ThreadChatServicing
    let operationProvider: any SyncClientOperationProviding
    private var syncAfterLocalChange: (@MainActor () async -> Void)?
    private(set) var participants: DailyChallengeParticipants
    private(set) var messages: [ThreadChatMessage] = []
    private(set) var threadID: UUID?
    private(set) var isLoading = true
    /// Becomes true once the screen has read this phone's copy of the chat.
    private(set) var hasReadStore = false
    var notice: Notice?
    /// Older messages may exist on the server than the ones this phone has. The chat opens
    /// on the newest page, and the person scrolling up loads the rest.
    private(set) var hasOlderMessages = false
    var isLoadingOlderMessages = false
    /// The server said the oldest message of the chat is already on this phone.
    var hasReachedChatStart = false
    /// The message or answer the next send replies to, shown above the composer.
    var replyTarget: ThreadChatReplyTarget?
    /// The user's own message whose text the composer is changing.
    var editTarget: ThreadChatMessage?
    /// The user's own message waiting for them to confirm taking it back.
    var deleteTarget: ThreadChatMessage?
    /// Changes when the composer should take focus, for example after picking a reply.
    var composerFocusRequest = 0
    /// Typing dots and read receipts.
    let presence: ThreadChatPresenceModel
    /// The reactions on the page's answers, as this phone last saved them. A message
    /// carries its own.
    private(set) var savedAnswerReactions: [DailyAnswerReaction] = []
    /// The user's reactions that the saved copy doesn't show yet. They show at once and
    /// stay until the saved copy agrees or the server turns them down.
    let reactionEditor = ReactionEditor()
    /// True while the chat is on screen and the app is in front, so reading counts.
    private var isScreenActive = false
    /// Which days the server has heard, during this visit, that the partner's answer was
    /// seen, or is hearing it now.
    private var answerSeenUploads: [UUID: AnswerSeenUpload] = [:]
    private enum AnswerSeenUpload { case sending, sent }
    private var newestPartnerMessageID: UUID?
    private var hasQueuedThreadCreation = false
    var isQueueing = false
    /// Counts reads of the store. A read that finishes after a newer one started
    /// holds older data, so it must not replace what the newer read showed.
    private var readGeneration = 0
    /// Failed messages the screen has already shown. `nil` until the first read, so
    /// a failure from an earlier visit shows its red icon but raises no banner.
    private var seenFailedOperationIDs: Set<UUID>?

    /// Opens the chat of `subject`. A question's chat passes its `question`, the day the page
    /// opened from, and `focusesNewest` opens the page on the question's newest day instead,
    /// for a chat opened from a message or the Home card. A memory's or a story's chat passes
    /// the `header` that says what the conversation is about.
    init(
        subject: ThreadChatSubject,
        coupleID: UUID,
        header: ThreadChatHeader? = nil,
        question: DailyChallengeQuestion? = nil,
        participants: DailyChallengeParticipants,
        focusesNewest: Bool = false,
        service: (any ThreadChatServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        syncAfterLocalChange: (@MainActor () async -> Void)? = nil
    ) {
        self.subject = subject
        self.coupleID = coupleID
        self.header = header
        self.question = question
        self.participants = participants
        self.focusesNewest = focusesNewest
        let service = service ?? ThreadChatServiceFactory.makeDefault()
        self.service = service
        presence = ThreadChatPresenceModel(coupleID: coupleID, subject: subject, service: service)
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.syncAfterLocalChange = syncAfterLocalChange
    }

    /// A question's chat. `focusesNewest` opens the page on the question's newest day instead
    /// of on `question`'s own day.
    convenience init(
        question: DailyChallengeQuestion,
        participants: DailyChallengeParticipants,
        focusesNewest: Bool = false,
        service: (any ThreadChatServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        syncAfterLocalChange: (@MainActor () async -> Void)? = nil
    ) {
        self.init(
            subject: .question(question.questionID),
            coupleID: question.coupleID,
            question: question,
            participants: participants,
            focusesNewest: focusesNewest,
            service: service,
            operationProvider: operationProvider,
            syncAfterLocalChange: syncAfterLocalChange
        )
    }

    /// Every day of the question, oldest first. The server's list decides what exists and
    /// what is readable. The day the page was opened from fills in until it has answered.
    /// Empty in a memory's or a story's chat.
    var rounds: [DailyChallengeQuestion] {
        guard let question else { return [] }
        return DailyChatRounds.merged(loaded: loadedRounds, entry: question, serverConfirmed: roundsAreConfirmed)
    }

    /// A question's chat opens once any day of the question has both answers. A memory's or a
    /// story's chat is open to both partners from the start.
    var isChatAvailable: Bool {
        guard participants.currentUserID != nil else { return false }
        return question == nil || DailyChatRounds.isChatAvailable(rounds)
    }

    /// The days as the page draws them. `celebratingInstanceID` is the day whose
    /// partner-choice match plays its small celebration.
    func chatRounds(celebrating celebratingInstanceID: UUID? = nil) -> [DailyChatRound] {
        let chatIsOpen = DailyChatRounds.isChatAvailable(rounds)
        return rounds.map {
            DailyChatRound(
                question: $0,
                participants: participants,
                chatIsOpen: chatIsOpen,
                celebratesMatch: $0.id == celebratingInstanceID
            )
        }
    }

    /// Where the page opens: the newest message when people have written after the day
    /// it opens on, otherwise the start of that day.
    var openingScroll: DailyChatRounds.OpeningScroll {
        DailyChatRounds.openingScroll(rounds: rounds, focusing: focusedInstanceID, messages: messages)
    }

    /// A message failed to send at least once. Only then does the screen say it is
    /// saved on this phone, so a normal send never flashes that line.
    var hasHeldMessages: Bool {
        messages.contains { $0.isSending && $0.isHeldOnPhone }
    }

    func refreshParticipants(_ participants: DailyChallengeParticipants) {
        self.participants = participants
    }

    /// The question changes while the screen is open, for example when the partner
    /// answers and the chat opens up.
    func refreshQuestion(_ question: DailyChallengeQuestion) {
        guard question.id == self.question?.id else { return }
        self.question = question
    }

    /// The server's list of days has arrived.
    var hasLoadedRounds: Bool { loadedRounds != nil }

    /// The question's newest day. It is the one just answered when the page opens
    /// straight from the answer flow.
    var newestRoundID: UUID? { rounds.last?.id }

    /// Reads this phone's copy of the chat. Called before the screen opens, so its
    /// first frame already shows every message and nothing moves in after it appears.
    func prepare() async {
        guard let ownerUserID = participants.currentUserID, isChatAvailable else { return }
        await readStore(ownerUserID: ownerUserID)
    }

    func load() async {
        defer { isLoading = false }
        guard let ownerUserID = participants.currentUserID, isChatAvailable else {
            notice = .unavailable
            return
        }

        await readStore(ownerUserID: ownerUserID)

        // The days come first, so an earlier day shows before the messages arrive. A failed
        // read keeps the days already on screen.
        if question != nil, (try? await service.refreshRounds(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            questionID: subject.id
        )) != nil {
            roundsAreConfirmed = true
            await readStore(ownerUserID: ownerUserID)
        }

        do {
            let summaries = try await service.refreshThreadSummaries(ownerUserID: ownerUserID)
            threadID = chatThreadID(in: summaries) ?? threadID
            if let threadID {
                _ = try await service.refreshMessages(
                    ownerUserID: ownerUserID,
                    subjectID: subject.id,
                    threadID: threadID
                )
                await readStore(ownerUserID: ownerUserID)
            }
        } catch {
            // Without a thread there is nothing missing, and the composer still works.
            // Only a thread that exists but cannot be read is a load error.
            if !error.isCancellation, threadID != nil, messages.isEmpty {
                notice = .loadFailed(PaeoniaFailure(error))
            }
        }
    }

    /// Re-reads the thread, the cached messages, and the messages still sending.
    func readStore(ownerUserID: UUID) async {
        readGeneration += 1
        let generation = readGeneration
        let cachedSummaries = await service.cachedThreadSummaries(ownerUserID: ownerUserID)
        // The thread never goes back to nil, so a late read may still set it.
        threadID = chatThreadID(in: cachedSummaries) ?? threadID
        var cachedRounds: DailyQuestionChatRoundsRow?
        if question != nil {
            cachedRounds = await service.cachedRounds(ownerUserID: ownerUserID, questionID: subject.id)
        }
        let cached = await service.cachedMessages(ownerUserID: ownerUserID, subjectID: subject.id)
        let pending = await service.pendingMessages(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            subjectID: subject.id
        )
        let isCreatingThread = await service.hasPendingThreadCreation(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            subjectID: subject.id
        )
        guard generation == readGeneration else { return }
        if let cachedRounds, cachedRounds.isForCouple(coupleID) {
            loadedRounds = cachedRounds.rounds()
            threadID = cachedRounds.threadID ?? threadID
            savedAnswerReactions = cachedRounds.reactions
        }
        hasQueuedThreadCreation = isCreatingThread
        messages = ThreadChatMessage.visibleOrdered(remote: cached, optimistic: pending)
        dropTargetsOfDeletedMessages()
        dropSavedPendingReactions(ownerUserID: ownerUserID)
        // Removed messages are left out of the cache, so a count of what is shown cannot tell
        // whether older ones exist. A short chat costs one extra read at the top, which ends it.
        hasOlderMessages = !hasReachedChatStart && cached.contains { !$0.isSending && !$0.sendFailed }
        hasReadStore = true
        raiseNoticeForNewFailures()
        let newestPartner = messages.last { $0.senderUserID != ownerUserID }?.id
        if newestPartner != newestPartnerMessageID {
            if newestPartnerMessageID != nil || newestPartner != nil { presence.partnerMessageArrived() }
            newestPartnerMessageID = newestPartner
        }
        await markShownAsSeen(ownerUserID: ownerUserID)
        markReadOnServerIfActive()
        markAnswerSeenOnServerIfActive()
    }

    /// The screen is open, so everything it shows counts as seen: every revealed partner
    /// answer, the delivered messages, and their notifications.
    private func markShownAsSeen(ownerUserID: UUID) async {
        for round in rounds where round.hasRevealedPartnerAnswer {
            await service.markPartnerAnswerSeen(ownerUserID: ownerUserID, instanceID: round.id)
        }
        // Notification Center can be slow to answer, so the chat doesn't wait on it.
        let shownMessageIDs = Set(messages.map(\.id))
        let shownInstanceIDs = Set(rounds.map(\.id))
        let isQuestionChat = question != nil
        Task {
            if isQuestionChat {
                await DeliveredNotifications.clearQuestion(
                    instanceIDs: shownInstanceIDs,
                    shownMessageIDs: shownMessageIDs
                )
            } else {
                await DeliveredNotifications.clearMessages(shownMessageIDs)
            }
        }
        let newestDelivered = messages.filter { !$0.isSending && !$0.sendFailed }.map(\.createdAt).max()
        if let threadID, let newestDelivered {
            await service.markThreadRead(ownerUserID: ownerUserID, threadID: threadID, through: newestDelivered)
        }
    }

    /// The thread of this couple's chat about the subject, if the summaries list it.
    private func chatThreadID(in summaries: [ThreadChatSummary]) -> UUID? {
        summaries.first { $0.subject == subject && $0.coupleID == coupleID }?.threadID
    }

    private func raiseNoticeForNewFailures() {
        let failed = Set(messages.filter(\.sendFailed).compactMap(\.clientOperationID))
        if let seen = seenFailedOperationIDs, !failed.isSubset(of: seen) {
            notice = .deliveryFailed
        }
        seenFailedOperationIDs = (seenFailedOperationIDs ?? []).union(failed)
    }

    func dismissNotice() {
        notice = nil
    }

    func syncInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await syncAfterLocalChange?()
            // The send confirmation lands in the cache. A full reload here could
            // overwrite a newer live result with an older server read.
            guard let ownerUserID = participants.currentUserID else { return }
            await readStore(ownerUserID: ownerUserID)
        }
    }
}

// MARK: - Sending, typing, and reading

extension ThreadChatViewModel {
    /// Queues a message. `failedOperationID` is the operation of a failed message the
    /// person tapped to send again. The new message replaces it and keeps its reply.
    func send(
        _ text: String,
        replacingFailed failedOperationID: UUID? = nil,
        replyTo retriedReply: ThreadChatItemID? = nil
    ) async -> Bool {
        await send(text, photos: [], replacingFailed: failedOperationID, replyTo: retriedReply)
    }

    func send(
        _ text: String,
        photos: [ThreadChatPhoto],
        replacingFailed failedOperationID: UUID?,
        replyTo retriedReply: ThreadChatItemID?
    ) async -> Bool {
        guard let ownerUserID = participants.currentUserID, isChatAvailable else {
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

        let reply = failedOperationID == nil ? replyTarget?.id : retriedReply
        let photosPayload = photosPayload(for: photos)
        do {
            try await queue(ownerUserID: ownerUserID, replacingFailed: failedOperationID) { createThread in
                _ = try await service.queueMessage(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    subject: subject,
                    threadID: threadID,
                    body: body,
                    photos: photosPayload,
                    createThread: createThread,
                    replyTo: reply,
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
    private func photosPayload(for photos: [ThreadChatPhoto]) -> ThreadChatPhotosPayload? {
        guard !photos.isEmpty else { return nil }
        return ThreadChatPhotosPayload(
            messageID: UUID(),
            items: photos.compactMap { photo in
                photo.data.map { data in
                    ThreadChatPhotosPayload.Item(
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
    func queue(
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
        guard isScreenActive else { return }
        for round in rounds where round.hasRevealedPartnerAnswer && round.partnerAnswerSeenAt == nil {
            guard answerSeenUploads[round.id] == nil else { continue }
            answerSeenUploads[round.id] = .sending
            let instanceID = round.id
            Task {
                let sent = await service.markPartnerAnswerSeenOnServer(instanceID: instanceID)
                answerSeenUploads[instanceID] = sent ? .sent : nil
            }
        }
    }
}
