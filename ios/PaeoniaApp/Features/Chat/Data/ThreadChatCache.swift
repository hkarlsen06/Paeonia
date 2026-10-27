import Foundation

protocol ThreadChatCaching: Actor {
    func summaries(ownerUserID: UUID) -> [ThreadChatSummary]
    func messages(ownerUserID: UUID, subjectID: UUID) -> [ThreadChatMessage]
    /// Keeps the summaries. Returns whether they differ from what was kept.
    @discardableResult
    func saveSummaries(_ summaries: [ThreadChatSummary], ownerUserID: UUID) -> Bool
    func saveMessages(
        _ messages: [ThreadChatMessage],
        ownerUserID: UUID,
        subjectID: UUID
    )
    func append(_ message: ThreadChatMessage, ownerUserID: UUID)
    func markFailed(ownerUserID: UUID, clientOperationID: UUID)
    /// Removes a message that failed to send, so a retry replaces it. Messages that
    /// are still sending or already sent are left alone.
    func discardFailed(ownerUserID: UUID, clientOperationID: UUID)
    /// Removes a message that is still sending or failed because the user took it back.
    func discardUnsent(ownerUserID: UUID, subjectID: UUID, clientOperationID: UUID)
    /// Shows a sent message as deleted, with no text, files or reactions, and clears the
    /// chat's preview when it was the newest message. Returns the media files the message
    /// had, so the caller can remove their cached copies.
    @discardableResult
    func markDeleted(ownerUserID: UUID, subjectID: UUID, messageID: UUID, at date: Date) -> [UUID]
    /// Like `markDeleted`, for a message whose chat is not known, such as one named in a push.
    /// Returns the media files the message had.
    @discardableResult
    func markDeletedInAnyChat(ownerUserID: UUID, messageID: UUID, at date: Date) -> [UUID]
    // swiftlint:disable:next function_parameter_count
    func confirm(
        ownerUserID: UUID,
        subject: ThreadChatSubject,
        coupleID: UUID,
        clientOperationID: UUID,
        threadID: UUID,
        messageID: UUID,
        body: String,
        senderUserID: UUID,
        createdAt: Date
    )
    func clearAll()
    /// Counts purges. A writer that suspends between reading and saving reads this
    /// first, then saves with `saveMessages(_:ownerUserID:subjectID:unlessPurgedSince:)`.
    func purgeGeneration() -> Int
    /// Like `saveMessages`, but writes nothing when `clearAll()` ran after `generation`
    /// was read. Returns whether it wrote.
    @discardableResult
    func saveMessages(
        _ messages: [ThreadChatMessage],
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// Like `saveMessages(_:ownerUserID:subjectID:unlessPurgedSince:)`, for a one-shot
    /// read that can be older than the cache. Confirmed cached messages that the read
    /// lacks and that are newer than its newest message stay.
    @discardableResult
    func mergeMessages(
        _ messages: [ThreadChatMessage],
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// Like `saveSummaries`, but writes nothing when `clearAll()` ran after `generation`
    /// was read. Returns whether it wrote.
    @discardableResult
    func saveSummaries(
        _ summaries: [ThreadChatSummary],
        ownerUserID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// The finished game last saved on this phone.
    func gameResult(ownerUserID: UUID, subjectID: UUID) -> GameConversationResult?
    @discardableResult
    func saveGameResult(
        _ result: GameConversationResult?, ownerUserID: UUID, subjectID: UUID, unlessPurgedSince generation: Int
    ) -> Bool
    /// The question's rounds as the server last sent them, so the page opens offline.
    func rounds(ownerUserID: UUID, subjectID: UUID) -> DailyQuestionChatRoundsRow?
    /// Keeps the question's rounds, unless `clearAll()` ran after `generation` was read.
    /// Returns whether it wrote.
    @discardableResult
    func saveRounds(
        _ rounds: DailyQuestionChatRoundsRow,
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// When this user last saw each thread, keyed by thread id. Only kept on this phone.
    func readMarks(ownerUserID: UUID) -> [UUID: Date]
    /// Records that the user has seen the thread up to `date`. An older date changes
    /// nothing. Returns whether it wrote.
    @discardableResult
    func markRead(ownerUserID: UUID, threadID: UUID, through date: Date) -> Bool
    /// Questions whose page the user has opened since the partner's answer showed up.
    /// Only kept on this phone.
    func seenPartnerAnswers(ownerUserID: UUID) -> Set<UUID>
    /// Records that the user has seen the partner's answer. Returns whether it wrote.
    @discardableResult
    func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) -> Bool
}

extension ThreadChatCaching {
    /// Adds a page of older messages to the confirmed ones already kept, unless
    /// `clearAll()` ran after `generation` was read. Runs without suspending, so no
    /// live result lands between the read and the save. Returns whether it wrote.
    @discardableResult
    func mergeOlderMessages(
        _ older: [ThreadChatMessage],
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == purgeGeneration() else { return false }
        let confirmed = messages(ownerUserID: ownerUserID, subjectID: subjectID)
            .filter { !$0.isSending && !$0.sendFailed }
        saveMessages(confirmed + older, ownerUserID: ownerUserID, subjectID: subjectID)
        return true
    }

    /// Drops the confirmed cached messages from before `cursor`, unless `clearAll()` ran after
    /// `generation` was read. Runs without suspending, like `mergeOlderMessages`.
    @discardableResult
    func trimMessages(
        before cursor: ThreadChatMessageCursor,
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == purgeGeneration() else { return false }
        let kept = messages(ownerUserID: ownerUserID, subjectID: subjectID).filter { message in
            message.isSending || message.sendFailed
                || (message.createdAt, message.id.uuidString) >= (cursor.createdAt, cursor.messageID.uuidString)
        }
        saveMessages(kept, ownerUserID: ownerUserID, subjectID: subjectID)
        return true
    }

    func gameResult(ownerUserID _: UUID, subjectID _: UUID) -> GameConversationResult? { nil }
    func saveGameResult(_: GameConversationResult?, ownerUserID _: UUID, subjectID _: UUID, unlessPurgedSince _: Int)
        -> Bool
    { false }
    func rounds(ownerUserID _: UUID, subjectID _: UUID) -> DailyQuestionChatRoundsRow? { nil }
    @discardableResult
    func saveRounds(
        _: DailyQuestionChatRoundsRow,
        ownerUserID _: UUID,
        subjectID _: UUID,
        unlessPurgedSince _: Int
    ) -> Bool { false }
    func readMarks(ownerUserID _: UUID) -> [UUID: Date] { [:] }
    @discardableResult
    func markRead(ownerUserID _: UUID, threadID _: UUID, through _: Date) -> Bool { false }
    func seenPartnerAnswers(ownerUserID _: UUID) -> Set<UUID> { [] }
    @discardableResult
    func markPartnerAnswerSeen(ownerUserID _: UUID, instanceID _: UUID) -> Bool { false }
}

/// Keeps the chat on disk, one file per user for the summaries and marks, and one file per
/// chat subject for its messages and rounds. A user's files are read once and then held in
/// memory, and a change writes only the file it touched, and only when something differs.
actor FileThreadChatCache: ThreadChatCaching {
    static let shared = FileThreadChatCache()

    private let files: ThreadChatCacheFiles
    private var generation = 0
    private var cores: [UUID: ThreadChatCoreDocument] = [:]
    /// Per user, the subject files read so far, keyed by subject id.
    private var subjectDocuments: [UUID: [String: ThreadChatSubjectDocument]] = [:]

    init(directoryURL: URL = FileThreadChatCache.defaultDirectoryURL()) {
        files = ThreadChatCacheFiles(directoryURL: directoryURL)
    }

    func summaries(ownerUserID: UUID) -> [ThreadChatSummary] {
        core(ownerUserID).summaries
    }

    func messages(ownerUserID: UUID, subjectID: UUID) -> [ThreadChatMessage] {
        subjectDocument(ownerUserID, subjectID.uuidString).messages
    }

    @discardableResult
    func saveSummaries(_ summaries: [ThreadChatSummary], ownerUserID: UUID) -> Bool {
        updateCore(ownerUserID) { $0.summaries = summaries }
    }

    func saveMessages(
        _ messages: [ThreadChatMessage],
        ownerUserID: UUID,
        subjectID: UUID
    ) {
        updateSubject(ownerUserID, subjectID.uuidString) {
            $0.messages = ThreadChatMessage.visibleOrdered(remote: messages, optimistic: $0.messages)
        }
    }

    func append(_ message: ThreadChatMessage, ownerUserID: UUID) {
        let appended = updateSubject(ownerUserID, message.subjectID.uuidString) { document in
            // A confirmation that ran first already stored the final copy. Adding the
            // sending copy again would show a sent message as sending.
            if let operationID = message.clientOperationID,
               document.messages.contains(where: { $0.clientOperationID == operationID && !$0.isSending }) {
                return
            }
            document.messages.removeAll { $0.clientOperationID == message.clientOperationID }
            document.messages.append(message)
            document.messages.sort { $0.createdAt < $1.createdAt }
        }
        if appended { updateCore(ownerUserID) { $0.updateSummary(for: message) } }
    }

    func markFailed(ownerUserID: UUID, clientOperationID: UUID) {
        for key in subjectKeys(ownerUserID) {
            let found = updateSubject(ownerUserID, key) { document in
                guard let index = document.messages.firstIndex(where: { $0.clientOperationID == clientOperationID })
                else { return }
                let message = document.messages[index]
                document.messages[index] = ThreadChatMessage(
                    id: message.id,
                    threadID: message.threadID,
                    subjectID: message.subjectID,
                    senderUserID: message.senderUserID,
                    body: message.body,
                    createdAt: message.createdAt,
                    clientOperationID: clientOperationID,
                    isSending: false,
                    sendFailed: true,
                    voice: message.voice,
                    photos: message.photos,
                    replyTo: message.replyTo
                )
            }
            if found { return }
        }
    }

    func discardFailed(ownerUserID: UUID, clientOperationID: UUID) {
        for key in subjectKeys(ownerUserID) {
            updateSubject(ownerUserID, key) { document in
                document.messages.removeAll { $0.clientOperationID == clientOperationID && $0.sendFailed }
            }
        }
    }

    func discardUnsent(ownerUserID: UUID, subjectID: UUID, clientOperationID: UUID) {
        updateSubject(ownerUserID, subjectID.uuidString) { document in
            document.messages.removeAll { $0.clientOperationID == clientOperationID && $0.isUnsent }
        }
    }

    // swiftlint:disable:next function_parameter_count
    func confirm(
        ownerUserID: UUID,
        subject: ThreadChatSubject,
        coupleID: UUID,
        clientOperationID: UUID,
        threadID: UUID,
        messageID: UUID,
        body: String,
        senderUserID: UUID,
        createdAt: Date
    ) {
        let send = ThreadChatConfirmedSend(
            subject: subject,
            coupleID: coupleID,
            clientOperationID: clientOperationID,
            threadID: threadID,
            messageID: messageID,
            body: body,
            senderUserID: senderUserID,
            createdAt: createdAt
        )
        updateSubject(ownerUserID, subject.id.uuidString) { $0.storeConfirmedMessage(send) }
        updateCore(ownerUserID) { $0.updateSummary(for: send) }
    }

    func purgeGeneration() -> Int {
        generation
    }

    @discardableResult
    func saveMessages(
        _ messages: [ThreadChatMessage],
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveMessages(messages, ownerUserID: ownerUserID, subjectID: subjectID)
        return true
    }

    @discardableResult
    func mergeMessages(
        _ messages: [ThreadChatMessage],
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        let cached = self.messages(ownerUserID: ownerUserID, subjectID: subjectID)
        saveMessages(
            ThreadChatMessage.keepingNewerCached(messages, cached: cached),
            ownerUserID: ownerUserID,
            subjectID: subjectID
        )
        return true
    }

    @discardableResult
    func saveSummaries(
        _ summaries: [ThreadChatSummary],
        ownerUserID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveSummaries(summaries, ownerUserID: ownerUserID)
        return true
    }

    func gameResult(ownerUserID: UUID, subjectID: UUID) -> GameConversationResult? {
        subjectDocument(ownerUserID, subjectID.uuidString).gameResult
    }

    @discardableResult
    func saveGameResult(
        _ result: GameConversationResult?, ownerUserID: UUID, subjectID: UUID, unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        updateSubject(ownerUserID, subjectID.uuidString) { $0.gameResult = result }
        return true
    }

    func rounds(ownerUserID: UUID, subjectID: UUID) -> DailyQuestionChatRoundsRow? {
        subjectDocument(ownerUserID, subjectID.uuidString).rounds
    }

    @discardableResult
    func saveRounds(
        _ rounds: DailyQuestionChatRoundsRow,
        ownerUserID: UUID,
        subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        updateSubject(ownerUserID, subjectID.uuidString) { $0.rounds = rounds }
        return true
    }

    func readMarks(ownerUserID: UUID) -> [UUID: Date] {
        Dictionary(
            core(ownerUserID).readThroughByThreadID.compactMap { key, date in
                UUID(uuidString: key).map { ($0, date) }
            },
            uniquingKeysWith: max
        )
    }

    @discardableResult
    func markRead(ownerUserID: UUID, threadID: UUID, through date: Date) -> Bool {
        let key = threadID.uuidString
        if let current = core(ownerUserID).readThroughByThreadID[key], current >= date { return false }
        return updateCore(ownerUserID) { $0.readThroughByThreadID[key] = date }
    }

    func seenPartnerAnswers(ownerUserID: UUID) -> Set<UUID> {
        Set(core(ownerUserID).seenPartnerAnswerInstanceIDs.compactMap(UUID.init(uuidString:)))
    }

    @discardableResult
    func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) -> Bool {
        let key = instanceID.uuidString
        guard !core(ownerUserID).seenPartnerAnswerInstanceIDs.contains(key) else { return false }
        return updateCore(ownerUserID) {
            $0.seenPartnerAnswerInstanceIDs.append(key)
            $0.trimSeenPartnerAnswers()
        }
    }

    func clearAll() {
        generation += 1
        cores = [:]
        subjectDocuments = [:]
        files.removeAll()
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThreadChatCache", isDirectory: true)
    }

    // MARK: - Memory and disk

    private func core(_ ownerUserID: UUID) -> ThreadChatCoreDocument {
        if let loaded = cores[ownerUserID] { return loaded }
        let loaded = files.read(ThreadChatCoreDocument.self, from: files.coreURL(ownerUserID))
            ?? ThreadChatCoreDocument()
        cores[ownerUserID] = loaded
        return loaded
    }

    /// Applies the change, and writes the file only when the document differs afterwards.
    @discardableResult
    func updateCore(_ ownerUserID: UUID, _ change: (inout ThreadChatCoreDocument) -> Void) -> Bool {
        let before = core(ownerUserID)
        var document = before
        change(&document)
        guard document != before else { return false }
        cores[ownerUserID] = document
        files.write(document, to: files.coreURL(ownerUserID))
        return true
    }

    func subjectDocument(_ ownerUserID: UUID, _ key: String) -> ThreadChatSubjectDocument {
        if let loaded = subjectDocuments[ownerUserID]?[key] { return loaded }
        let loaded = files.read(ThreadChatSubjectDocument.self, from: files.subjectURL(ownerUserID, key))
            ?? ThreadChatSubjectDocument()
        subjectDocuments[ownerUserID, default: [:]][key] = loaded
        return loaded
    }

    /// Every subject the user has a file for, or has read a document of.
    func subjectKeys(_ ownerUserID: UUID) -> Set<String> {
        files.subjectKeys(ownerUserID).union((subjectDocuments[ownerUserID] ?? [:]).keys)
    }

    @discardableResult
    func updateSubject(
        _ ownerUserID: UUID,
        _ key: String,
        _ change: (inout ThreadChatSubjectDocument) -> Void
    ) -> Bool {
        let before = subjectDocument(ownerUserID, key)
        var document = before
        change(&document)
        guard document != before else { return false }
        subjectDocuments[ownerUserID, default: [:]][key] = document
        files.write(document, to: files.subjectURL(ownerUserID, key))
        return true
    }
}
