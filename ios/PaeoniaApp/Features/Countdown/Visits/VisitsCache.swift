import Foundation

/// The couple's visits and list as the server last sent them, for one signed-in person, so
/// the Us tab card and the visit screen show them offline and right after launch.
protocol VisitsCaching: Actor {
    func visits(ownerUserID: UUID) -> CoupleVisits
    /// The live feed's write.
    func save(_ visits: CoupleVisits, ownerUserID: UUID)
    /// A write the server confirmed, applied before the live feed brings the same change.
    func apply(_ write: VisitsWrite, ownerUserID: UUID)
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileVisitsCache: VisitsCaching {
    static let shared = FileVisitsCache()

    /// Bump when a stored type gains a required field. A file with another version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL

    init(directoryURL: URL = FileVisitsCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VisitsCache", isDirectory: true)
    }

    func visits(ownerUserID: UUID) -> CoupleVisits {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return CoupleVisits()
        }
        return envelope.visits
    }

    func save(_ visits: CoupleVisits, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, visits: visits)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    func apply(_ write: VisitsWrite, ownerUserID: UUID) {
        save(visits(ownerUserID: ownerUserID).applying([write]), ownerUserID: ownerUserID)
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
        let visits: CoupleVisits
    }
}

/// A cache that lives in memory, for the developer scenarios and tests.
actor InMemoryVisitsCache: VisitsCaching {
    private var stored: [UUID: CoupleVisits]

    init(_ visits: CoupleVisits = CoupleVisits(), ownerUserID: UUID? = nil) {
        stored = ownerUserID.map { [$0: visits] } ?? [:]
    }

    func visits(ownerUserID: UUID) -> CoupleVisits {
        stored[ownerUserID] ?? CoupleVisits()
    }

    func save(_ visits: CoupleVisits, ownerUserID: UUID) {
        stored[ownerUserID] = visits
    }

    func apply(_ write: VisitsWrite, ownerUserID: UUID) {
        stored[ownerUserID] = visits(ownerUserID: ownerUserID).applying([write])
    }

    func clearAll() {
        stored.removeAll()
    }
}
