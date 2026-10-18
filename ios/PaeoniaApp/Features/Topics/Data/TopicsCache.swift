import Foundation

/// What this phone keeps of the topics for one signed-in person, so the Topics card,
/// the shelf and any topic opened before show at once and offline.
nonisolated struct TopicsCacheDocument: Codable, Equatable, Sendable {
    var overview: RemoteTopicsOverview?
    /// Each opened topic's last read, by topic key.
    var details: [String: RemoteTopicDetail] = [:]
    /// The questions this phone has shown in each topic, by topic key. A topic that
    /// gains questions later shows them as new.
    var seenQuestionIDs: [String: Set<UUID>] = [:]
    /// Topics whose finished moment this phone has shown.
    var celebratedTopicKeys: Set<String> = []
}

protocol TopicsCaching: Actor {
    func document(ownerUserID: UUID) -> TopicsCacheDocument
    func saveOverview(_ overview: RemoteTopicsOverview, ownerUserID: UUID)
    func saveDetail(_ detail: RemoteTopicDetail, ownerUserID: UUID)
    /// A topic the couple can no longer open leaves the phone.
    func removeDetail(topicKey: String, ownerUserID: UUID)
    func markSeen(_ questionIDs: Set<UUID>, topicKey: String, ownerUserID: UUID)
    func markCelebrated(topicKey: String, ownerUserID: UUID)
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileTopicsCache: TopicsCaching {
    static let shared = FileTopicsCache()

    /// Bump when a stored type gains a required field. A file with another version
    /// reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL
    /// Read once per person and kept, so a burst of live writes doesn't reread disk.
    private var loaded: [UUID: TopicsCacheDocument] = [:]

    init(directoryURL: URL = FileTopicsCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TopicsCache", isDirectory: true)
    }

    func document(ownerUserID: UUID) -> TopicsCacheDocument {
        if let document = loaded[ownerUserID] {
            return document
        }
        let document = read(ownerUserID: ownerUserID)
        loaded[ownerUserID] = document
        return document
    }

    func saveOverview(_ overview: RemoteTopicsOverview, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.overview = overview }
    }

    func saveDetail(_ detail: RemoteTopicDetail, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.details[detail.topic.topicKey] = detail }
    }

    func removeDetail(topicKey: String, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.details[topicKey] = nil }
    }

    func markSeen(_ questionIDs: Set<UUID>, topicKey: String, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { document in
            document.seenQuestionIDs[topicKey, default: []].formUnion(questionIDs)
        }
    }

    func markCelebrated(topicKey: String, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.celebratedTopicKeys.insert(topicKey) }
    }

    func clearAll() {
        loaded = [:]
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func update(ownerUserID: UUID, _ change: (inout TopicsCacheDocument) -> Void) {
        var document = document(ownerUserID: ownerUserID)
        let before = document
        change(&document)
        guard document != before else { return }
        loaded[ownerUserID] = document
        write(document, ownerUserID: ownerUserID)
    }

    private func read(ownerUserID: UUID) -> TopicsCacheDocument {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return TopicsCacheDocument()
        }
        return envelope.document
    }

    private func write(_ document: TopicsCacheDocument, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, document: document)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let document: TopicsCacheDocument
    }
}
