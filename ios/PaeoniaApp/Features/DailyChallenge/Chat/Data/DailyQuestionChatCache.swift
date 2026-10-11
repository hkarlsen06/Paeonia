import Foundation

protocol DailyQuestionChatCaching: Actor {
    func summaries(ownerUserID: UUID) -> [DailyQuestionThreadSummary]
    func messages(ownerUserID: UUID, instanceID: UUID) -> [DailyQuestionChatMessage]
    func saveSummaries(_ summaries: [DailyQuestionThreadSummary], ownerUserID: UUID)
    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID
    )
    func append(_ message: DailyQuestionChatMessage, ownerUserID: UUID)
    func markFailed(ownerUserID: UUID, clientOperationID: UUID)
    /// Removes a message that failed to send, so a retry replaces it. Messages that
    /// are still sending or already sent are left alone.
    func discardFailed(ownerUserID: UUID, clientOperationID: UUID)
    func confirm(
        ownerUserID: UUID,
        instanceID: UUID,
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
    /// first, then saves with `saveMessages(_:ownerUserID:instanceID:unlessPurgedSince:)`.
    func purgeGeneration() -> Int
    /// Like `saveMessages`, but writes nothing when `clearAll()` ran after `generation`
    /// was read. Returns whether it wrote.
    @discardableResult
    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool
    /// Like `saveMessages(_:ownerUserID:instanceID:unlessPurgedSince:)`, for a one-shot
    /// read that can be older than the cache. Confirmed cached messages that the read
    /// lacks and that are newer than its newest message stay.
    @discardableResult
    func mergeMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID,
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
}

actor FileDailyQuestionChatCache: DailyQuestionChatCaching {
    static let shared = FileDailyQuestionChatCache()

    private static let schemaVersion = 2
    private let directoryURL: URL
    private var generation = 0

    init(directoryURL: URL = FileDailyQuestionChatCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    func summaries(ownerUserID: UUID) -> [DailyQuestionThreadSummary] {
        document(ownerUserID: ownerUserID).summaries
    }

    func messages(ownerUserID: UUID, instanceID: UUID) -> [DailyQuestionChatMessage] {
        document(ownerUserID: ownerUserID).messagesByInstanceID[instanceID.uuidString] ?? []
    }

    func saveSummaries(_ summaries: [DailyQuestionThreadSummary], ownerUserID: UUID) {
        var document = document(ownerUserID: ownerUserID)
        document.summaries = summaries
        save(document, ownerUserID: ownerUserID)
    }

    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID
    ) {
        var document = document(ownerUserID: ownerUserID)
        let cached = document.messagesByInstanceID[instanceID.uuidString] ?? []
        document.messagesByInstanceID[instanceID.uuidString] = DailyQuestionChatMessage.visibleOrdered(
            remote: messages,
            optimistic: cached
        )
        save(document, ownerUserID: ownerUserID)
    }

    func append(_ message: DailyQuestionChatMessage, ownerUserID: UUID) {
        var document = document(ownerUserID: ownerUserID)
        var messages = document.messagesByInstanceID[message.instanceID.uuidString] ?? []
        // A confirmation that ran first already stored the final copy. Adding the
        // sending copy again would show a sent message as sending.
        if let operationID = message.clientOperationID,
           messages.contains(where: { $0.clientOperationID == operationID && !$0.isSending }) {
            return
        }
        messages.removeAll { $0.clientOperationID == message.clientOperationID }
        messages.append(message)
        document.messagesByInstanceID[message.instanceID.uuidString] = messages.sorted {
            $0.createdAt < $1.createdAt
        }

        if let threadID = message.threadID,
           let index = document.summaries.firstIndex(where: { $0.threadID == threadID }) {
            let summary = document.summaries[index]
            document.summaries[index] = DailyQuestionThreadSummary(
                threadID: summary.threadID,
                coupleID: summary.coupleID,
                instanceID: summary.instanceID,
                createdAt: summary.createdAt,
                updatedAt: message.createdAt,
                lastMessageID: message.id,
                lastMessageAt: message.createdAt,
                lastMessageSenderUserID: message.senderUserID,
                lastMessageBody: message.body
            )
        }
        save(document, ownerUserID: ownerUserID)
    }

    func markFailed(ownerUserID: UUID, clientOperationID: UUID) {
        var document = document(ownerUserID: ownerUserID)
        for key in Array(document.messagesByInstanceID.keys) {
            guard
                let messages = document.messagesByInstanceID[key],
                let index = messages.firstIndex(where: { $0.clientOperationID == clientOperationID })
            else { continue }
            let message = messages[index]
            document.messagesByInstanceID[key]?[index] = DailyQuestionChatMessage(
                id: message.id,
                threadID: message.threadID,
                instanceID: message.instanceID,
                senderUserID: message.senderUserID,
                body: message.body,
                createdAt: message.createdAt,
                clientOperationID: clientOperationID,
                isSending: false,
                sendFailed: true
            )
            save(document, ownerUserID: ownerUserID)
            return
        }
    }

    func discardFailed(ownerUserID: UUID, clientOperationID: UUID) {
        var document = document(ownerUserID: ownerUserID)
        let before = document.messagesByInstanceID
        for key in Array(document.messagesByInstanceID.keys) {
            document.messagesByInstanceID[key]?.removeAll {
                $0.clientOperationID == clientOperationID && $0.sendFailed
            }
        }
        guard document.messagesByInstanceID != before else { return }
        save(document, ownerUserID: ownerUserID)
    }

    func confirm(
        ownerUserID: UUID,
        instanceID: UUID,
        coupleID: UUID,
        clientOperationID: UUID,
        threadID: UUID,
        messageID: UUID,
        body: String,
        senderUserID: UUID,
        createdAt: Date
    ) {
        var document = document(ownerUserID: ownerUserID)
        let key = instanceID.uuidString
        let index = document.messagesByInstanceID[key]?.firstIndex(where: {
            $0.clientOperationID == clientOperationID
        })
        let confirmed = DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt,
            clientOperationID: clientOperationID,
            isSending: false
        )
        if let index {
            document.messagesByInstanceID[key]?[index] = confirmed
        } else {
            document.messagesByInstanceID[key, default: []].append(confirmed)
        }

        if let summaryIndex = document.summaries.firstIndex(where: { $0.instanceID == instanceID }) {
            let summary = document.summaries[summaryIndex]
            document.summaries[summaryIndex] = DailyQuestionThreadSummary(
                threadID: threadID,
                coupleID: summary.coupleID,
                instanceID: instanceID,
                createdAt: summary.createdAt,
                updatedAt: createdAt,
                lastMessageID: messageID,
                lastMessageAt: createdAt,
                lastMessageSenderUserID: senderUserID,
                lastMessageBody: body
            )
        } else {
            document.summaries.append(
                DailyQuestionThreadSummary(
                    threadID: threadID,
                    coupleID: coupleID,
                    instanceID: instanceID,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    lastMessageID: messageID,
                    lastMessageAt: createdAt,
                    lastMessageSenderUserID: senderUserID,
                    lastMessageBody: body
                )
            )
        }
        save(document, ownerUserID: ownerUserID)
    }

    func purgeGeneration() -> Int {
        generation
    }

    @discardableResult
    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveMessages(messages, ownerUserID: ownerUserID, instanceID: instanceID)
        return true
    }

    @discardableResult
    func mergeMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        let cached = self.messages(ownerUserID: ownerUserID, instanceID: instanceID)
        saveMessages(
            DailyQuestionChatMessage.keepingNewerCached(messages, cached: cached),
            ownerUserID: ownerUserID,
            instanceID: instanceID
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

    func clearAll() {
        generation += 1
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyQuestionChatCache", isDirectory: true)
    }

    private func document(ownerUserID: UUID) -> CacheDocument {
        guard let data = try? Data(contentsOf: fileURL(ownerUserID: ownerUserID)),
              let envelope = try? decoder().decode(CacheEnvelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID else {
            return CacheDocument()
        }
        return envelope.document
    }

    private func save(_ document: CacheDocument, ownerUserID: UUID) {
        let envelope = CacheEnvelope(
            schemaVersion: Self.schemaVersion,
            ownerUserID: ownerUserID,
            document: document
        )
        guard let data = try? encoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(ownerUserID: ownerUserID), options: .atomic)
    }

    private func fileURL(ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json")
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated private struct CacheEnvelope: Codable {
    let schemaVersion: Int
    let ownerUserID: UUID
    let document: CacheDocument
}

nonisolated private struct CacheDocument: Codable {
    var summaries: [DailyQuestionThreadSummary] = []
    var messagesByInstanceID: [String: [DailyQuestionChatMessage]] = [:]
}
