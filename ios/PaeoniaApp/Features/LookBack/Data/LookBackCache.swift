import Foundation

/// What the last successful look-back read returned, so Home can show the card on the first
/// frame of a cold launch instead of waiting for the network.
nonisolated struct LookBackCacheEntry: Codable, Equatable, Sendable {
    /// The couple the item belongs to. Nil when the app did not know the couple yet.
    var coupleID: UUID?
    /// Nil when the last read found nothing to show.
    var item: LookBackItem?
}

nonisolated protocol LookBackCaching: Sendable {
    /// The saved entry for the user, or nil when there is none, it is for another couple, or the
    /// file cannot be read. Never throws.
    func load(ownerUserID: UUID, coupleID: UUID?) -> LookBackCacheEntry?
    func save(_ entry: LookBackCacheEntry, ownerUserID: UUID)
    /// How many times the cache has been cleared. A read takes the count before it starts.
    func purgeCount() -> Int
    /// Saves unless the cache was cleared after `purgeCount` was read, so a read that was in flight
    /// during a privacy purge never writes private content back. Returns whether it saved.
    func save(_ entry: LookBackCacheEntry, ownerUserID: UUID, unlessPurgedSince purgeCount: Int) -> Bool
    /// Deletes everything. The privacy purge calls this when the user leaves or loses the relationship.
    func clearAll()
}

/// One JSON file per user under Application Support. A file from another schema version reads as a miss.
nonisolated final class FileLookBackCache: @unchecked Sendable, LookBackCaching {
    static let shared = FileLookBackCache()

    private static let schemaVersion = 1
    private let directoryURL: URL
    private let lock = NSLock()
    private var purges = 0

    nonisolated init(directoryURL: URL = FileLookBackCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LookBackCache", isDirectory: true)
    }

    nonisolated func load(ownerUserID: UUID, coupleID: UUID?) -> LookBackCacheEntry? {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else { return nil }
        if let coupleID, let cached = envelope.entry.coupleID, cached != coupleID { return nil }
        return envelope.entry
    }

    nonisolated func save(_ entry: LookBackCacheEntry, ownerUserID: UUID) {
        lock.withLock { write(entry, ownerUserID: ownerUserID) }
    }

    nonisolated func purgeCount() -> Int {
        lock.withLock { purges }
    }

    nonisolated func save(_ entry: LookBackCacheEntry, ownerUserID: UUID, unlessPurgedSince purgeCount: Int) -> Bool {
        lock.withLock {
            guard purges == purgeCount else { return false }
            write(entry, ownerUserID: ownerUserID)
            return true
        }
    }

    nonisolated func clearAll() {
        lock.withLock {
            purges += 1
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    /// Call with the lock held.
    private nonisolated func write(_ entry: LookBackCacheEntry, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, entry: entry)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: .atomic)
    }

    private nonisolated func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }

    private nonisolated struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let entry: LookBackCacheEntry
    }
}
