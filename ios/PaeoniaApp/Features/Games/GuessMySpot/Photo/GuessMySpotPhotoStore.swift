import Foundation

/// The stripped photos of sends that have not reached the server, one file per
/// person and round. The queued send carries only the round id, so the queue
/// stays small, and the photo is here while the phone is offline. The send
/// handler removes the file once the server has the round.
nonisolated protocol GuessMySpotPhotoStoring: Sendable {
    func photo(ownerUserID: UUID, roundID: UUID) -> Data?
    func remove(ownerUserID: UUID, roundID: UUID)
    func draftTicket(ownerUserID: UUID) -> GuessMySpotDraftTicket
    func draft(ownerUserID: UUID, coupleID: UUID) throws -> GuessMySpotStoredDraft?
    @discardableResult
    func saveDraft(_ draft: GuessMySpotStoredDraft, ownerUserID: UUID, coupleID: UUID,
                   ticket: GuessMySpotDraftTicket) throws -> Bool
    func discardDraft(roundID: UUID, ownerUserID: UUID, coupleID: UUID, keepingPhoto: Bool) throws
    /// The privacy purge calls this on sign-out and when a relationship ends.
    func clearAll()
}

nonisolated final class FileGuessMySpotPhotoStore: GuessMySpotPhotoStoring, @unchecked Sendable {
    static let shared = FileGuessMySpotPhotoStore()

    private let directoryURL: URL
    private let lock = NSLock()
    private var generation = 0

    init(directoryURL: URL = FileGuessMySpotPhotoStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    /// In Application Support, so the system never removes a photo that waits to be sent.
    static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuessMySpotPhotos", isDirectory: true)
    }

    func photo(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { try? Data(contentsOf: fileURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func remove(ownerUserID: UUID, roundID: UUID) {
        lock.withLock { try? FileManager.default.removeItem(at: fileURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func clearAll() {
        lock.withLock {
            generation += 1
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func fileURL(ownerUserID: UUID, roundID: UUID) -> URL {
        directoryURL
            .appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("\(roundID.uuidString.lowercased()).jpg", isDirectory: false)
    }
}

/// For tests and the developer scenarios.
nonisolated final class InMemoryGuessMySpotPhotoStore: GuessMySpotPhotoStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var photos: [String: Data] = [:]
    private var drafts: [String: GuessMySpotStoredDraft] = [:]
    private var generation = 0

    init() {}

    func save(_ jpeg: Data, ownerUserID: UUID, roundID: UUID) throws {
        lock.withLock { photos[key(ownerUserID, roundID)] = jpeg }
    }

    func photo(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { photos[key(ownerUserID, roundID)] }
    }

    func remove(ownerUserID: UUID, roundID: UUID) {
        lock.withLock { photos[key(ownerUserID, roundID)] = nil }
    }

    func clearAll() {
        lock.withLock {
            generation += 1
            photos = [:]
            drafts = [:]
        }
    }

    private func key(_ owner: UUID, _ round: UUID) -> String {
        "\(owner.uuidString):\(round.uuidString)"
    }
}

extension FileGuessMySpotPhotoStore {
    func draftTicket(ownerUserID: UUID) -> GuessMySpotDraftTicket {
        lock.withLock {
            GuessMySpotDraftTicket(generation: generation,
                                   privacy: LocalPrivacyWriteGuard.shared.token(ownerUserID: ownerUserID))
        }
    }

    func draft(ownerUserID: UUID, coupleID: UUID) throws -> GuessMySpotStoredDraft? {
        try lock.withLock {
            let url = draftURL(ownerUserID: ownerUserID, coupleID: coupleID)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let metadata = try JSONDecoder().decode(GuessMySpotDraftMetadata.self, from: Data(contentsOf: url))
            let jpeg = try Data(contentsOf: fileURL(ownerUserID: ownerUserID, roundID: metadata.roundID))
            return metadata.draft(jpeg: jpeg)
        }
    }

    func saveDraft(_ draft: GuessMySpotStoredDraft, ownerUserID: UUID, coupleID: UUID,
                   ticket: GuessMySpotDraftTicket) throws -> Bool {
        try lock.withLock {
            guard ticket.generation == generation else { return false }
            return try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: ticket.privacy) {
                let url = draftURL(ownerUserID: ownerUserID, coupleID: coupleID)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let photoURL = fileURL(ownerUserID: ownerUserID, roundID: draft.roundID)
                if !FileManager.default.fileExists(atPath: photoURL.path) {
                    try draft.photo.jpeg.write(to: photoURL,
                                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                try JSONEncoder().encode(GuessMySpotDraftMetadata(draft)).write(
                    to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
                return true
            }
        }
    }

    func discardDraft(roundID: UUID, ownerUserID: UUID, coupleID: UUID, keepingPhoto: Bool) throws {
        try lock.withLock {
            let url = draftURL(ownerUserID: ownerUserID, coupleID: coupleID)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let metadata = try JSONDecoder().decode(GuessMySpotDraftMetadata.self, from: Data(contentsOf: url))
            guard metadata.roundID == roundID else { return }
            try FileManager.default.removeItem(at: url)
            if !keepingPhoto {
                try FileManager.default.removeItem(at: fileURL(ownerUserID: ownerUserID, roundID: roundID))
            }
        }
    }

    private func draftURL(ownerUserID: UUID, coupleID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("\(coupleID.uuidString.lowercased()).draft.json")
    }
}

extension InMemoryGuessMySpotPhotoStore {
    func draftTicket(ownerUserID: UUID) -> GuessMySpotDraftTicket {
        lock.withLock {
            GuessMySpotDraftTicket(generation: generation,
                                   privacy: LocalPrivacyWriteGuard.shared.token(ownerUserID: ownerUserID))
        }
    }

    func draft(ownerUserID: UUID, coupleID: UUID) throws -> GuessMySpotStoredDraft? {
        lock.withLock { drafts[key(ownerUserID, coupleID)] }
    }

    func saveDraft(_ draft: GuessMySpotStoredDraft, ownerUserID: UUID, coupleID: UUID,
                   ticket: GuessMySpotDraftTicket) throws -> Bool {
        try lock.withLock {
            guard ticket.generation == generation else { return false }
            return try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: ticket.privacy) {
                drafts[key(ownerUserID, coupleID)] = draft
                photos[key(ownerUserID, draft.roundID)] = draft.photo.jpeg
                return true
            }
        }
    }

    func discardDraft(roundID: UUID, ownerUserID: UUID, coupleID: UUID, keepingPhoto: Bool) throws {
        lock.withLock {
            guard drafts[key(ownerUserID, coupleID)]?.roundID == roundID else { return }
            drafts[key(ownerUserID, coupleID)] = nil
            if !keepingPhoto { photos[key(ownerUserID, roundID)] = nil }
        }
    }
}
