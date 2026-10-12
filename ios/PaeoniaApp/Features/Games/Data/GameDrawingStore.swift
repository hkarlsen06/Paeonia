import Foundation

/// Drawings kept on this phone as files. A draft is the drawer's own unsent
/// drawing, so closing the app mid-drawing loses nothing. A rescued drawing is
/// one whose word was refused by the server. It waits for the drawer's next
/// round. A downloaded drawing is the partner's, kept so a replay works offline.
nonisolated protocol GameDrawingStoring: Sendable {
    func draft(ownerUserID: UUID, roundID: UUID) -> Data?
    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID)
    func removeDraft(ownerUserID: UUID, roundID: UUID)
    func rescuedDrawing(ownerUserID: UUID) -> Data?
    func saveRescuedDrawing(_ data: Data, ownerUserID: UUID)
    func removeRescuedDrawing(ownerUserID: UUID)
    func downloadedDrawing(mediaAssetID: UUID) -> Data?
    func saveDownloadedDrawing(_ data: Data, mediaAssetID: UUID)
    /// Removes the partner's drawings and keeps this person's own unsent ones.
    func clearDownloads()
    /// Removes everything, the person's own unsent drawings included.
    func clearAll()
}

nonisolated extension GameDrawingStoring {
    /// Applies a privacy purge. Losing access for a while keeps the person's own
    /// unsent drawings, like the widget and memory drafts. Signing out and a
    /// permanent loss remove them too.
    func purge(for scope: LocalPrivacyPurgeScope) {
        if scope == .relationshipAccessHidden {
            clearDownloads()
        } else {
            clearAll()
        }
    }
}

nonisolated final class FileGameDrawingStore: GameDrawingStoring, @unchecked Sendable {
    static let shared = FileGameDrawingStore()

    private let directoryURL: URL
    private let lock = NSLock()

    init(directoryURL: URL = FileGameDrawingStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameDrawings", isDirectory: true)
    }

    func draft(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { try? Data(contentsOf: draftURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID) {
        lock.withLock { write(data, to: draftURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func removeDraft(ownerUserID: UUID, roundID: UUID) {
        lock.withLock { try? FileManager.default.removeItem(at: draftURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func rescuedDrawing(ownerUserID: UUID) -> Data? {
        lock.withLock { try? Data(contentsOf: rescuedURL(ownerUserID: ownerUserID)) }
    }

    func saveRescuedDrawing(_ data: Data, ownerUserID: UUID) {
        lock.withLock { write(data, to: rescuedURL(ownerUserID: ownerUserID)) }
    }

    func removeRescuedDrawing(ownerUserID: UUID) {
        lock.withLock { try? FileManager.default.removeItem(at: rescuedURL(ownerUserID: ownerUserID)) }
    }

    func downloadedDrawing(mediaAssetID: UUID) -> Data? {
        lock.withLock { try? Data(contentsOf: downloadURL(mediaAssetID: mediaAssetID)) }
    }

    func saveDownloadedDrawing(_ data: Data, mediaAssetID: UUID) {
        lock.withLock { write(data, to: downloadURL(mediaAssetID: mediaAssetID)) }
    }

    func clearDownloads() {
        lock.withLock {
            try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent("downloads", isDirectory: true))
        }
    }

    func clearAll() {
        lock.withLock {
            guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic])
    }

    private func draftURL(ownerUserID: UUID, roundID: UUID) -> URL {
        directoryURL
            .appendingPathComponent("drafts", isDirectory: true)
            .appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(roundID.uuidString.lowercased() + ".pkdrawing", isDirectory: false)
    }

    private func rescuedURL(ownerUserID: UUID) -> URL {
        directoryURL
            .appendingPathComponent("rescued", isDirectory: true)
            .appendingPathComponent(ownerUserID.uuidString.lowercased() + ".pkdrawing", isDirectory: false)
    }

    private func downloadURL(mediaAssetID: UUID) -> URL {
        directoryURL
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(mediaAssetID.uuidString.lowercased() + ".pkdrawing", isDirectory: false)
    }
}

/// For tests and the developer scenarios.
nonisolated final class InMemoryGameDrawingStore: GameDrawingStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var drafts: [String: Data] = [:]
    private var rescued: [UUID: Data] = [:]
    private var downloads: [UUID: Data] = [:]

    init() {}

    func draft(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { drafts["\(ownerUserID)/\(roundID)"] }
    }

    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID) {
        lock.withLock { drafts["\(ownerUserID)/\(roundID)"] = data }
    }

    func removeDraft(ownerUserID: UUID, roundID: UUID) {
        lock.withLock { drafts["\(ownerUserID)/\(roundID)"] = nil }
    }

    func rescuedDrawing(ownerUserID: UUID) -> Data? {
        lock.withLock { rescued[ownerUserID] }
    }

    func saveRescuedDrawing(_ data: Data, ownerUserID: UUID) {
        lock.withLock { rescued[ownerUserID] = data }
    }

    func removeRescuedDrawing(ownerUserID: UUID) {
        lock.withLock { rescued[ownerUserID] = nil }
    }

    func downloadedDrawing(mediaAssetID: UUID) -> Data? {
        lock.withLock { downloads[mediaAssetID] }
    }

    func saveDownloadedDrawing(_ data: Data, mediaAssetID: UUID) {
        lock.withLock { downloads[mediaAssetID] = data }
    }

    func clearDownloads() {
        lock.withLock { downloads = [:] }
    }

    func clearAll() {
        lock.withLock {
            drafts = [:]
            rescued = [:]
            downloads = [:]
        }
    }
}
