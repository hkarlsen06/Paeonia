import Foundation

/// The couple's countdowns and birthdays as the server last sent them, for one
/// signed-in person, so the timeline shows them offline and right after launch.
protocol CoupleDatesCaching: Actor {
    func dates(ownerUserID: UUID) -> CoupleDates
    /// The live feed's write.
    func save(_ dates: CoupleDates, ownerUserID: UUID)
    /// A write the server confirmed, applied before the live feed brings the same change.
    func apply(_ write: CoupleDatesWrite, ownerUserID: UUID)
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileCoupleDatesCache: CoupleDatesCaching {
    static let shared = FileCoupleDatesCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 2

    private let directoryURL: URL

    init(directoryURL: URL = FileCoupleDatesCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleDatesCache", isDirectory: true)
    }

    func dates(ownerUserID: UUID) -> CoupleDates {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return CoupleDates()
        }
        return envelope.dates
    }

    func save(_ dates: CoupleDates, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, dates: dates)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    func apply(_ write: CoupleDatesWrite, ownerUserID: UUID) {
        save(dates(ownerUserID: ownerUserID).applying([write]), ownerUserID: ownerUserID)
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
        let dates: CoupleDates
    }
}
