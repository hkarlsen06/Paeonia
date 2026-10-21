import Foundation

/// The couple's reactions on stories, memories, drawings and game creations as the server last
/// sent them, for one signed-in person, so they show offline and right after launch.
protocol ReactionsCaching: Actor {
    func rows(ownerUserID: UUID) -> [ReactionRow]
    /// The live feed's write.
    func save(_ rows: [ReactionRow], ownerUserID: UUID)
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileReactionsCache: ReactionsCaching {
    static let shared = FileReactionsCache()

    /// Bump when a stored type gains a required field. A file with another version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL

    init(directoryURL: URL = FileReactionsCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReactionsCache", isDirectory: true)
    }

    func rows(ownerUserID: UUID) -> [ReactionRow] {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return []
        }
        return envelope.rows
    }

    func save(_ rows: [ReactionRow], ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, rows: rows)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let rows: [ReactionRow]
    }
}
