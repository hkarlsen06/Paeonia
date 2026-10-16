import Foundation

/// The couple's stories and notes as the server last sent them, for one signed-in person, so
/// Home and the Stories archive show them offline and right after launch.
protocol StoriesCaching: Actor {
    func snapshot(ownerUserID: UUID) -> StoriesSnapshot
    /// The live feed's write, or a change this phone made and the server accepted.
    func save(_ snapshot: StoriesSnapshot, ownerUserID: UUID)
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileStoriesCache: StoriesCaching {
    static let shared = FileStoriesCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 2

    private let directoryURL: URL

    init(directoryURL: URL = FileStoriesCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoriesCache", isDirectory: true)
    }

    func snapshot(ownerUserID: UUID) -> StoriesSnapshot {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return StoriesSnapshot()
        }
        return envelope.snapshot
    }

    func save(_ snapshot: StoriesSnapshot, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, snapshot: snapshot)
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
        let snapshot: StoriesSnapshot
    }
}
