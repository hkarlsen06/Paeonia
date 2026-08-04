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
}

actor FileDailyQuestionChatCache: DailyQuestionChatCaching {
    static let shared = FileDailyQuestionChatCache()

    private static let schemaVersion = 2
    private let directoryURL: URL

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
            guard let index = document.messagesByInstanceID[key]?.firstIndex(where: {
                $0.clientOperationID == clientOperationID
            }) else { continue }
            document.messagesByInstanceID[key]![index] = DailyQuestionChatMessage(
                id: document.messagesByInstanceID[key]![index].id,
                threadID: document.messagesByInstanceID[key]![index].threadID,
                instanceID: document.messagesByInstanceID[key]![index].instanceID,
                senderUserID: document.messagesByInstanceID[key]![index].senderUserID,
                body: document.messagesByInstanceID[key]![index].body,
                createdAt: document.messagesByInstanceID[key]![index].createdAt,
                clientOperationID: clientOperationID,
                isSending: false,
                sendFailed: true
            )
            save(document, ownerUserID: ownerUserID)
            return
        }
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
            document.messagesByInstanceID[key]![index] = confirmed
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

    func clearAll() {
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
