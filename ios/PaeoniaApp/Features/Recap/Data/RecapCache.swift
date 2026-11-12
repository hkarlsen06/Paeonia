import Foundation

nonisolated struct RecapCacheEntry: Codable, Equatable, Sendable {
    var coupleID: UUID?
    var recaps: [AnniversaryRecap]
}

nonisolated protocol RecapCaching: Sendable {
    func load(ownerUserID: UUID, coupleID: UUID?) -> RecapCacheEntry?
    func purgeCount() -> Int
    func save(_ entry: RecapCacheEntry, ownerUserID: UUID, unlessPurgedSince purgeCount: Int) -> Bool
    func clearAll()
}

nonisolated final class FileRecapCache: @unchecked Sendable, RecapCaching {
    static let shared = FileRecapCache()

    private static let schemaVersion = 1
    private let directoryURL: URL
    private let lock = NSLock()
    private var purges = 0

    init(directoryURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RecapCache", isDirectory: true)) {
        self.directoryURL = directoryURL
    }

    func load(ownerUserID: UUID, coupleID: UUID?) -> RecapCacheEntry? {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else { return nil }
        if let coupleID, let cached = envelope.entry.coupleID, cached != coupleID { return nil }
        return envelope.entry
    }

    func purgeCount() -> Int {
        lock.withLock { purges }
    }

    func save(_ entry: RecapCacheEntry, ownerUserID: UUID, unlessPurgedSince purgeCount: Int) -> Bool {
        lock.withLock {
            guard purges == purgeCount else { return false }
            let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, entry: entry)
            guard let data = try? JSONEncoder().encode(envelope) else { return false }
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try? data.write(to: fileURL(for: ownerUserID), options: .atomic)
            return true
        }
    }

    func clearAll() {
        lock.withLock {
            purges += 1
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let entry: RecapCacheEntry
    }
}
