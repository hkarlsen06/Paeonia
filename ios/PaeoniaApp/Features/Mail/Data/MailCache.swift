import Foundation

/// The couple's letters as the server last sent them, and the letter this person is writing,
/// for one signed-in person. Only what `letters:get_letters` returned is stored, so a sealed
/// letter, or the note and photo of one not opened yet, never reach the partner's phone.
protocol MailCaching: Actor {
    func snapshot(ownerUserID: UUID) -> MailSnapshot
    /// The live feed's write.
    func save(_ snapshot: MailSnapshot, ownerUserID: UUID)
    /// Counts the privacy purges. A change this phone started reads it first.
    var purgeGeneration: Int { get }
    /// Applies a change this phone made and the server accepted. Does nothing and returns
    /// false when a purge ran since `generation`.
    func update(
        ownerUserID: UUID, ifGeneration generation: Int, _ change: @Sendable (inout MailSnapshot) -> Void
    ) -> Bool
    func draft(ownerUserID: UUID) -> LetterDraft?
    func draftPhoto(ownerUserID: UUID) -> Data?
    /// Keeps the letter being written. A nil photo removes the saved one.
    func saveDraft(_ draft: LetterDraft, photo: Data?, ownerUserID: UUID, ifGeneration generation: Int)
    func clearDraft(ownerUserID: UUID)
    /// Removes every stored letter, when the person leaves the paired state.
    func clearAll()
    /// Removes every unsent letter, which only the author has seen.
    func clearDrafts()
}

actor FileMailCache: MailCaching {
    static let shared = FileMailCache()

    /// Bump when a stored type gains a required field. A file with another version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL
    private(set) var purgeGeneration = 0

    init(directoryURL: URL = FileMailCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailCache", isDirectory: true)
    }

    func snapshot(ownerUserID: UUID) -> MailSnapshot {
        read(Envelope<MailSnapshot>.self, from: lettersURL(ownerUserID), ownerUserID: ownerUserID) ?? MailSnapshot()
    }

    func save(_ snapshot: MailSnapshot, ownerUserID: UUID) {
        write(snapshot, to: lettersURL(ownerUserID), ownerUserID: ownerUserID)
    }

    func update(
        ownerUserID: UUID,
        ifGeneration generation: Int,
        _ change: @Sendable (inout MailSnapshot) -> Void
    ) -> Bool {
        guard generation == purgeGeneration else { return false }
        var updated = snapshot(ownerUserID: ownerUserID)
        change(&updated)
        save(updated, ownerUserID: ownerUserID)
        return true
    }

    func draft(ownerUserID: UUID) -> LetterDraft? {
        read(Envelope<LetterDraft>.self, from: draftURL(ownerUserID), ownerUserID: ownerUserID)
    }

    func draftPhoto(ownerUserID: UUID) -> Data? {
        try? Data(contentsOf: draftPhotoURL(ownerUserID))
    }

    func saveDraft(_ draft: LetterDraft, photo: Data?, ownerUserID: UUID, ifGeneration generation: Int) {
        guard generation == purgeGeneration else { return }
        write(draft, to: draftURL(ownerUserID), ownerUserID: ownerUserID)
        if let photo {
            try? photo.write(to: draftPhotoURL(ownerUserID), options: [.atomic, .completeFileProtection])
        } else {
            try? FileManager.default.removeItem(at: draftPhotoURL(ownerUserID))
        }
    }

    func clearDraft(ownerUserID: UUID) {
        try? FileManager.default.removeItem(at: draftURL(ownerUserID))
        try? FileManager.default.removeItem(at: draftPhotoURL(ownerUserID))
    }

    func clearAll() {
        purgeGeneration += 1
        remove(suffix: ".letters.json")
    }

    func clearDrafts() {
        purgeGeneration += 1
        remove(suffix: ".draft.json")
        remove(suffix: ".draft.photo")
    }

    private func remove(suffix: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil))
            ?? []
        for file in files where file.lastPathComponent.hasSuffix(suffix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func read<Value: Decodable>(_ type: Envelope<Value>.Type, from url: URL, ownerUserID: UUID) -> Value? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(type, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return nil
        }
        return envelope.value
    }

    private func write(_ value: some Codable, to url: URL, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, value: value)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func fileName(_ ownerUserID: UUID, _ suffix: String) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + suffix, isDirectory: false)
    }

    private func lettersURL(_ ownerUserID: UUID) -> URL { fileName(ownerUserID, ".letters.json") }
    private func draftURL(_ ownerUserID: UUID) -> URL { fileName(ownerUserID, ".draft.json") }
    private func draftPhotoURL(_ ownerUserID: UUID) -> URL { fileName(ownerUserID, ".draft.photo") }

    private struct Envelope<Value: Codable>: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let value: Value
    }
}
