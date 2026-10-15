import Foundation

/// The cache's files for each user: `core.json` for the summaries and marks, and one
/// `question-<id>.json` for each question's messages and rounds.
nonisolated struct DailyChatCacheFiles: Sendable {
    private static let schemaVersion = 5
    private static let questionFilePrefix = "question-"

    let directoryURL: URL

    func coreURL(_ ownerUserID: UUID) -> URL {
        ownerURL(ownerUserID).appendingPathComponent("core.json")
    }

    func questionURL(_ ownerUserID: UUID, _ key: String) -> URL {
        ownerURL(ownerUserID).appendingPathComponent("\(Self.questionFilePrefix)\(key).json")
    }

    /// The questions the user has a file for.
    func questionKeys(_ ownerUserID: UUID) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: ownerURL(ownerUserID).path)) ?? []
        return Set(names.compactMap { name in
            guard name.hasPrefix(Self.questionFilePrefix), name.hasSuffix(".json") else { return nil }
            return String(name.dropFirst(Self.questionFilePrefix.count).dropLast(".json".count))
        })
    }

    func read<Document: Codable>(_ type: Document.Type, from url: URL) -> Document? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? Self.decoder.decode(DailyChatCacheEnvelope<Document>.self, from: data),
              envelope.schemaVersion == Self.schemaVersion else { return nil }
        return envelope.document
    }

    func write<Document: Codable>(_ document: Document, to url: URL) {
        let envelope = DailyChatCacheEnvelope(schemaVersion: Self.schemaVersion, document: document)
        guard let data = try? Self.encoder.encode(envelope) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    func removeAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func ownerURL(_ ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
    }

    // Keeps milliseconds. Plain `.iso8601` drops them, which left read marks just
    // before the server's message times, so read chats came back as unread.
    private static var encoder: JSONEncoder { PaeoniaConvexClient.encoder }

    private static var decoder: JSONDecoder { PaeoniaConvexClient.decoder }
}
