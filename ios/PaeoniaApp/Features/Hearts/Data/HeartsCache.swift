import Foundation

/// What this phone keeps of the partner's hearts for one signed-in person, so
/// hearts that were already shown do not play again after a relaunch or while
/// the server's answer is on its way.
protocol HeartsCaching: Actor {
    func inbox(ownerUserID: UUID) -> HeartsInbox
    /// The live feed's write.
    func save(_ server: RemoteHeartsState, ownerUserID: UUID)
    /// Records that this phone showed the partner's hearts up to `total`.
    func markShown(upTo total: Int, ownerUserID: UUID)
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileHeartsCache: HeartsCaching {
    static let shared = FileHeartsCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL

    init(directoryURL: URL = FileHeartsCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HeartsCache", isDirectory: true)
    }

    func inbox(ownerUserID: UUID) -> HeartsInbox {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return HeartsInbox()
        }
        return envelope.inbox
    }

    func save(_ server: RemoteHeartsState, ownerUserID: UUID) {
        var inbox = inbox(ownerUserID: ownerUserID)
        inbox.apply(server)
        write(inbox, ownerUserID: ownerUserID)
    }

    func markShown(upTo total: Int, ownerUserID: UUID) {
        var inbox = inbox(ownerUserID: ownerUserID)
        inbox.markShown(upTo: total)
        write(inbox, ownerUserID: ownerUserID)
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func write(_ inbox: HeartsInbox, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, inbox: inbox)
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
        let inbox: HeartsInbox
    }
}
