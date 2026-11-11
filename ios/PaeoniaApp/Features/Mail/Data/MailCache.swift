import Foundation

/// This person's Mail as the server last sent it, and the letter they are writing, for one
/// signed-in person. Only what `letters:get_letters` returned is stored, so a sealed letter,
/// or the note and photo of one not opened yet, never reach the partner's phone.
protocol MailCaching: Actor {
    func snapshot(ownerUserID: UUID) -> MailSnapshot
    /// The live feed's write.
    func save(_ snapshot: MailSnapshot, ownerUserID: UUID)
    /// Counts the purges of the stored letters. A change this phone started reads it first.
    var purgeGeneration: Int { get }
    /// Counts the purges of the letter being written. Kept apart, since a purge that only
    /// hides the relationship for a while removes the letters and keeps the draft.
    var draftGeneration: Int { get }
    /// Applies a change this phone made and the server accepted. Does nothing and returns
    /// false when a purge ran since `generation`.
    func update(
        ownerUserID: UUID, ifGeneration generation: Int, _ change: @Sendable (inout MailSnapshot) -> Void
    ) -> Bool
    /// The letter being written, its photo, and the draft generation they were read in.
    func storedDraft(ownerUserID: UUID) -> StoredLetterDraft
    /// Keeps the letter being written, or removes it with its photo when nil. Removes photo
    /// files the draft no longer names. Does nothing and returns false when drafts were purged since `generation`.
    func saveDraft(_ draft: LetterDraft?, ownerUserID: UUID, ifGeneration generation: Int) -> Bool
    /// Keeps the bytes of a picked photo, before the draft that names it. Returns false when it
    /// could not, or when drafts were purged since `generation`.
    func saveDraftPhoto(_ data: Data, id: UUID, ownerUserID: UUID, ifGeneration generation: Int) -> Bool
    /// Records `shown` as the letter photos this phone may hold, and returns the ones recorded
    /// before that are not in it. The record outlives the app, so a letter deleted while the
    /// app was closed still has its photo removed.
    func trackPhotos(_ shown: Set<UUID>, ownerUserID: UUID) -> Set<UUID>
    /// Removes every stored letter, when the person leaves the paired state.
    func clearAll()
    /// Removes every unsent letter, which only the author has seen.
    func clearDrafts()
}

actor FileMailCache: MailCaching {
    static let shared = FileMailCache()

    /// Bump when a stored type gains a required field. A file with another version reads as empty.
    private static let schemaVersion = 3
    private static let draftPhotoSuffix = ".draft-photo"

    private let directoryURL: URL
    private(set) var purgeGeneration = 0
    private(set) var draftGeneration = 0

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

    func storedDraft(ownerUserID: UUID) -> StoredLetterDraft {
        let draft = read(Envelope<LetterDraft>.self, from: draftURL(ownerUserID), ownerUserID: ownerUserID)
        let photo = draft?.content.photo.flatMap { try? Data(contentsOf: draftPhotoURL(ownerUserID, $0.id)) }
        return StoredLetterDraft(draft: draft, photo: photo, generation: draftGeneration)
    }

    func saveDraft(_ draft: LetterDraft?, ownerUserID: UUID, ifGeneration generation: Int) -> Bool {
        guard generation == draftGeneration else { return false }
        if let draft {
            write(draft, to: draftURL(ownerUserID), ownerUserID: ownerUserID)
        } else {
            try? FileManager.default.removeItem(at: draftURL(ownerUserID))
        }
        let kept = draft?.content.photo.map { draftPhotoURL(ownerUserID, $0.id).lastPathComponent }
        let prefix = ownerUserID.uuidString.lowercased() + "."
        remove { $0.hasPrefix(prefix) && $0.hasSuffix(Self.draftPhotoSuffix) && $0 != kept }
        return true
    }

    func saveDraftPhoto(_ data: Data, id: UUID, ownerUserID: UUID, ifGeneration generation: Int) -> Bool {
        guard generation == draftGeneration else { return false }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        do {
            try data.write(to: draftPhotoURL(ownerUserID, id), options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    func trackPhotos(_ shown: Set<UUID>, ownerUserID: UUID) -> Set<UUID> {
        let url = photosURL(ownerUserID)
        let tracked = read(Envelope<Set<UUID>>.self, from: url, ownerUserID: ownerUserID) ?? []
        if tracked != shown { write(shown, to: url, ownerUserID: ownerUserID) }
        return tracked.subtracting(shown)
    }

    /// The purge removes the photos too, so their record goes with the letters.
    func clearAll() {
        purgeGeneration += 1
        remove { $0.hasSuffix(".letters.json") || $0.hasSuffix(".photos.json") }
        LocalStoreChanges.post(.mail, ownerUserID: nil)
    }

    /// Tells Mail, so a draft it read just before the purge leaves memory too.
    func clearDrafts() {
        draftGeneration += 1
        remove { $0.hasSuffix(".draft.json") || $0.hasSuffix(Self.draftPhotoSuffix) }
        LocalStoreChanges.post(.mail, ownerUserID: nil)
    }

    private func remove(where matches: (String) -> Bool) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil))
            ?? []
        for file in files where matches(file.lastPathComponent) {
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
    private func photosURL(_ ownerUserID: UUID) -> URL { fileName(ownerUserID, ".photos.json") }
    private func draftPhotoURL(_ ownerUserID: UUID, _ photoID: UUID) -> URL {
        fileName(ownerUserID, "." + photoID.uuidString.lowercased() + Self.draftPhotoSuffix)
    }

    private struct Envelope<Value: Codable>: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let value: Value
    }
}
