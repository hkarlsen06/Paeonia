import Foundation

protocol DailyQuestionChatCaching: Actor {
    func summaries(ownerUserID: UUID) -> [DailyQuestionThreadSummary]
    func messages(ownerUserID: UUID, questionID: UUID) -> [DailyQuestionChatMessage]
    /// Keeps the summaries. Returns whether they differ from what was kept.
    @discardableResult
    func saveSummaries(_ summaries: [DailyQuestionThreadSummary], ownerUserID: UUID) -> Bool
    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID
    )
    func append(_ message: DailyQuestionChatMessage, ownerUserID: UUID)
    func markFailed(ownerUserID: UUID, clientOperationID: UUID)
    /// Removes a message that failed to send, so a retry replaces it. Messages that
    /// are still sending or already sent are left alone.
    func discardFailed(ownerUserID: UUID, clientOperationID: UUID)
    // swiftlint:disable:next function_parameter_count
    func confirm(
        ownerUserID: UUID,
        questionID: UUID,
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
    /// first, then saves with `saveMessages(_:ownerUserID:questionID:unlessPurgedSince:)`.
    func purgeGeneration() -> Int
    /// Like `saveMessages`, but writes nothing when `clearAll()` ran after `generation`
    /// was read. Returns whether it wrote.
    @discardableResult
    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// Like `saveMessages(_:ownerUserID:questionID:unlessPurgedSince:)`, for a one-shot
    /// read that can be older than the cache. Confirmed cached messages that the read
    /// lacks and that are newer than its newest message stay.
    @discardableResult
    func mergeMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// Like `saveSummaries`, but writes nothing when `clearAll()` ran after `generation`
    /// was read. Returns whether it wrote.
    @discardableResult
    func saveSummaries(
        _ summaries: [DailyQuestionThreadSummary],
        ownerUserID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// The question's rounds as the server last sent them, so the page opens offline.
    func rounds(ownerUserID: UUID, questionID: UUID) -> DailyQuestionChatRoundsRow?
    /// Keeps the question's rounds, unless `clearAll()` ran after `generation` was read.
    /// Returns whether it wrote.
    @discardableResult
    func saveRounds(
        _ rounds: DailyQuestionChatRoundsRow,
        ownerUserID: UUID,
        questionID: UUID,
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

extension DailyQuestionChatCaching {
    /// Adds a page of older messages to the confirmed ones already kept, unless
    /// `clearAll()` ran after `generation` was read. Runs without suspending, so no
    /// live result lands between the read and the save. Returns whether it wrote.
    @discardableResult
    func mergeOlderMessages(
        _ older: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == purgeGeneration() else { return false }
        let confirmed = messages(ownerUserID: ownerUserID, questionID: questionID)
            .filter { !$0.isSending && !$0.sendFailed }
        saveMessages(confirmed + older, ownerUserID: ownerUserID, questionID: questionID)
        return true
    }

    func rounds(ownerUserID _: UUID, questionID _: UUID) -> DailyQuestionChatRoundsRow? { nil }
    @discardableResult
    func saveRounds(
        _: DailyQuestionChatRoundsRow,
        ownerUserID _: UUID,
        questionID _: UUID,
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
/// question for its messages and rounds. A user's files are read once and then held in
/// memory, and a change writes only the file it touched, and only when something differs.
actor FileDailyQuestionChatCache: DailyQuestionChatCaching {
    static let shared = FileDailyQuestionChatCache()

    private let files: DailyChatCacheFiles
    private var generation = 0
    private var cores: [UUID: DailyChatCoreDocument] = [:]
    /// Per user, the question files read so far, keyed by question id.
    private var questions: [UUID: [String: DailyChatQuestionDocument]] = [:]

    init(directoryURL: URL = FileDailyQuestionChatCache.defaultDirectoryURL()) {
        files = DailyChatCacheFiles(directoryURL: directoryURL)
    }

    func summaries(ownerUserID: UUID) -> [DailyQuestionThreadSummary] {
        core(ownerUserID).summaries
    }

    func messages(ownerUserID: UUID, questionID: UUID) -> [DailyQuestionChatMessage] {
        question(ownerUserID, questionID.uuidString).messages
    }

    @discardableResult
    func saveSummaries(_ summaries: [DailyQuestionThreadSummary], ownerUserID: UUID) -> Bool {
        updateCore(ownerUserID) { $0.summaries = summaries }
    }

    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID
    ) {
        updateQuestion(ownerUserID, questionID.uuidString) {
            $0.messages = DailyQuestionChatMessage.visibleOrdered(remote: messages, optimistic: $0.messages)
        }
    }

    func append(_ message: DailyQuestionChatMessage, ownerUserID: UUID) {
        let appended = updateQuestion(ownerUserID, message.questionID.uuidString) { document in
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
        for key in questionKeys(ownerUserID) {
            let found = updateQuestion(ownerUserID, key) { document in
                guard let index = document.messages.firstIndex(where: { $0.clientOperationID == clientOperationID })
                else { return }
                let message = document.messages[index]
                document.messages[index] = DailyQuestionChatMessage(
                    id: message.id,
                    threadID: message.threadID,
                    questionID: message.questionID,
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
        for key in questionKeys(ownerUserID) {
            updateQuestion(ownerUserID, key) { document in
                document.messages.removeAll { $0.clientOperationID == clientOperationID && $0.sendFailed }
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    func confirm(
        ownerUserID: UUID,
        questionID: UUID,
        coupleID: UUID,
        clientOperationID: UUID,
        threadID: UUID,
        messageID: UUID,
        body: String,
        senderUserID: UUID,
        createdAt: Date
    ) {
        let send = DailyChatConfirmedSend(
            questionID: questionID,
            coupleID: coupleID,
            clientOperationID: clientOperationID,
            threadID: threadID,
            messageID: messageID,
            body: body,
            senderUserID: senderUserID,
            createdAt: createdAt
        )
        updateQuestion(ownerUserID, questionID.uuidString) { $0.storeConfirmedMessage(send) }
        updateCore(ownerUserID) { $0.updateSummary(for: send) }
    }

    func purgeGeneration() -> Int {
        generation
    }

    @discardableResult
    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveMessages(messages, ownerUserID: ownerUserID, questionID: questionID)
        return true
    }

    @discardableResult
    func mergeMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        let cached = self.messages(ownerUserID: ownerUserID, questionID: questionID)
        saveMessages(
            DailyQuestionChatMessage.keepingNewerCached(messages, cached: cached),
            ownerUserID: ownerUserID,
            questionID: questionID
        )
        return true
    }

    @discardableResult
    func saveSummaries(
        _ summaries: [DailyQuestionThreadSummary],
        ownerUserID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveSummaries(summaries, ownerUserID: ownerUserID)
        return true
    }

    func rounds(ownerUserID: UUID, questionID: UUID) -> DailyQuestionChatRoundsRow? {
        question(ownerUserID, questionID.uuidString).rounds
    }

    @discardableResult
    func saveRounds(
        _ rounds: DailyQuestionChatRoundsRow,
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        updateQuestion(ownerUserID, questionID.uuidString) { $0.rounds = rounds }
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
        questions = [:]
        files.removeAll()
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyQuestionChatCache", isDirectory: true)
    }

    // MARK: - Memory and disk

    private func core(_ ownerUserID: UUID) -> DailyChatCoreDocument {
        if let loaded = cores[ownerUserID] { return loaded }
        let loaded = files.read(DailyChatCoreDocument.self, from: files.coreURL(ownerUserID)) ?? DailyChatCoreDocument()
        cores[ownerUserID] = loaded
        return loaded
    }

    /// Applies the change, and writes the file only when the document differs afterwards.
    @discardableResult
    private func updateCore(_ ownerUserID: UUID, _ change: (inout DailyChatCoreDocument) -> Void) -> Bool {
        let before = core(ownerUserID)
        var document = before
        change(&document)
        guard document != before else { return false }
        cores[ownerUserID] = document
        files.write(document, to: files.coreURL(ownerUserID))
        return true
    }

    private func question(_ ownerUserID: UUID, _ key: String) -> DailyChatQuestionDocument {
        if let loaded = questions[ownerUserID]?[key] { return loaded }
        let loaded = files.read(DailyChatQuestionDocument.self, from: files.questionURL(ownerUserID, key))
            ?? DailyChatQuestionDocument()
        questions[ownerUserID, default: [:]][key] = loaded
        return loaded
    }

    /// Every question the user has a file for, or has read a document of.
    private func questionKeys(_ ownerUserID: UUID) -> Set<String> {
        files.questionKeys(ownerUserID).union((questions[ownerUserID] ?? [:]).keys)
    }

    @discardableResult
    private func updateQuestion(
        _ ownerUserID: UUID,
        _ key: String,
        _ change: (inout DailyChatQuestionDocument) -> Void
    ) -> Bool {
        let before = question(ownerUserID, key)
        var document = before
        change(&document)
        guard document != before else { return false }
        questions[ownerUserID, default: [:]][key] = document
        files.write(document, to: files.questionURL(ownerUserID, key))
        return true
    }
}
