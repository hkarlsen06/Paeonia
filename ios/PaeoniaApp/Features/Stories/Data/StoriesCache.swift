import Foundation

/// The couple's stories and notes as the server last sent them, for one signed-in person, so
/// Home and the Stories archive show them offline and right after launch.
protocol StoriesCaching: Actor {
    func snapshot(ownerUserID: UUID) -> StoriesSnapshot
    /// The live feed's write.
    func save(_ snapshot: StoriesSnapshot, ownerUserID: UUID)
    /// Counts the privacy purges. A change this phone started reads it first.
    var purgeGeneration: Int { get }
    /// Applies a change this phone made and the server accepted, in one step, so a live
    /// feed write can't land between the read and the write. Does nothing and returns
    /// false when a purge ran since `generation`, so an answer that arrives late never
    /// brings back content the purge removed.
    func update(
        ownerUserID: UUID,
        ifGeneration generation: Int,
        _ change: @Sendable (inout StoriesSnapshot) -> Void
    ) -> Bool
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileStoriesCache: StoriesCaching {
    static let shared = FileStoriesCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 2

    private let directoryURL: URL
    private(set) var purgeGeneration = 0

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

    func update(
        ownerUserID: UUID,
        ifGeneration generation: Int,
        _ change: @Sendable (inout StoriesSnapshot) -> Void
    ) -> Bool {
        guard generation == purgeGeneration else { return false }
        var updated = snapshot(ownerUserID: ownerUserID)
        change(&updated)
        save(updated, ownerUserID: ownerUserID)
        return true
    }

    func clearAll() {
        purgeGeneration += 1
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
