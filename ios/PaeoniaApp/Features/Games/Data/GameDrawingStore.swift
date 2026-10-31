import Foundation
import PencilKit

/// Drawings kept on this phone as files. A draft is the drawer's own unsent
/// drawing, so closing the app mid-drawing loses nothing. A rescued drawing is
/// one whose word was refused by the server. It waits for the drawer's next
/// round. A downloaded drawing is the partner's, kept so a replay works offline.
/// A live snapshot is the partner's canvas as this person saw it when they
/// guessed it live. It fills the reveal after a relaunch until the partner's
/// sent drawing is downloaded.
nonisolated protocol GameDrawingStoring: Sendable {
    func draft(ownerUserID: UUID, roundID: UUID) -> Data?
    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID)
    func removeDraft(ownerUserID: UUID, roundID: UUID)
    func markDraftForPublication(ownerUserID: UUID, roundID: UUID) throws -> UUID
    @discardableResult
    func removePublishedDraft(_ publication: GameDrawingDraftPublication, ownerUserID: UUID,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws -> Bool
    func draftDescription(ownerUserID: UUID, coupleID: UUID, roundID: UUID?) throws -> String?
    func saveDraftDescription(_ text: String, ownerUserID: UUID, coupleID: UUID, roundID: UUID?,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws
    func removeDraftDescription(ownerUserID: UUID, roundID: UUID?)
    func moveDraftDescription(ownerUserID: UUID, from: UUID?, to: UUID?,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws
    /// Starts a save that runs in the background, and returns its ticket. Any
    /// later save or removal of this draft, background or not, makes the ticket
    /// stale.
    func beginDraftSave(ownerUserID: UUID, roundID: UUID) -> Int
    /// Saves the draft unless its ticket went stale, so a save that finishes late
    /// never undoes a newer draft or a removal.
    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID, ticket: Int)
    func rescuedDrawing(ownerUserID: UUID) -> Data?
    func saveRescuedDrawing(_ data: Data, ownerUserID: UUID)
    func removeRescuedDrawing(ownerUserID: UUID)
    func downloadedDrawing(mediaAssetID: UUID) -> Data?
    func saveDownloadedDrawing(_ data: Data, mediaAssetID: UUID)
    func liveSnapshot(ownerUserID: UUID, roundID: UUID) -> Data?
    /// Keeps one snapshot per person. A new one replaces the one before.
    func saveLiveSnapshot(_ data: Data, ownerUserID: UUID, roundID: UUID)
    func removeLiveSnapshot(ownerUserID: UUID, roundID: UUID)
    /// Removes the partner's drawings, live snapshots included, and keeps this
    /// person's own unsent ones.
    func clearDownloads()
    /// Removes everything, the person's own unsent drawings included.
    func clearAll()
}

nonisolated extension GameDrawingStoring {
    /// Saves a draft without holding up the main actor. The caller passes a copy
    /// of the drawing as drawn on a canvas of `side` points. Scaling to the
    /// canonical size, encoding and the write happen in the background.
    func saveDraftInBackground(_ drawing: PKDrawing, fromSide side: CGFloat, ownerUserID: UUID, roundID: UUID) {
        let ticket = beginDraftSave(ownerUserID: ownerUserID, roundID: roundID)
        Task.detached(priority: .utility) { [self] in
            let data = GameCanvas.canonical(drawing, fromSide: side).dataRepresentation()
            saveDraft(data, ownerUserID: ownerUserID, roundID: roundID, ticket: ticket)
        }
    }

    /// Applies a privacy purge. Losing access for a while keeps the person's own
    /// unsent drawings, like the widget and memory drafts. Signing out and a
    /// permanent loss remove them too.
    func purge(for scope: LocalPrivacyPurgeScope) {
        // The pictures of "Our drawings" held in memory go with the files.
        GameDrawingThumbnails.removeAll()
        if scope == .relationshipAccessHidden {
            clearDownloads()
        } else {
            clearAll()
        }
    }
}

/// Counts the saves and removals of each draft, to tell a background save that
/// a newer one overtook. The store's lock guards it.
nonisolated struct GameDraftTickets {
    private var latest: [String: Int] = [:]
    private var clearCount = 0
    private var publications: [String: UUID] = [:]

    private static func key(_ ownerUserID: UUID, _ roundID: UUID) -> String {
        "\(ownerUserID)/\(roundID)"
    }

    /// Makes every earlier ticket of this draft stale and returns a new one.
    mutating func next(_ ownerUserID: UUID, _ roundID: UUID) -> Int {
        let key = Self.key(ownerUserID, roundID)
        publications[key] = nil
        latest[key, default: 0] += 1
        return latest[key, default: 0] + clearCount
    }

    /// Makes every ticket of every draft stale.
    mutating func invalidateAll() {
        clearCount += 1
        publications = [:]
    }

    /// A newer save, including one still encoding, invalidates acceptance cleanup.
    /// File stores also persist this identity for acceptance after relaunch.
    mutating func markPublication(_ ownerUserID: UUID, _ roundID: UUID) -> UUID {
        let id = UUID()
        publications[Self.key(ownerUserID, roundID)] = id
        return id
    }

    func isCurrentPublication(_ id: UUID, _ ownerUserID: UUID, _ roundID: UUID) -> Bool {
        publications[Self.key(ownerUserID, roundID)] == id
    }

    func canRemovePersistedPublication(_ id: UUID, _ ownerUserID: UUID, _ roundID: UUID) -> Bool {
        latest[Self.key(ownerUserID, roundID)] == nil || isCurrentPublication(id, ownerUserID, roundID)
    }

    func isCurrent(_ ticket: Int, _ ownerUserID: UUID, _ roundID: UUID) -> Bool {
        ticket == latest[Self.key(ownerUserID, roundID), default: 0] + clearCount
    }
}

nonisolated final class FileGameDrawingStore: GameDrawingStoring, @unchecked Sendable {
    static let shared = FileGameDrawingStore()

    private let directoryURL: URL
    private let lock = NSLock()
    private var draftTickets = GameDraftTickets()

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
        lock.withLock {
            invalidatePublication(ownerUserID: ownerUserID, roundID: roundID)
            _ = draftTickets.next(ownerUserID, roundID)
            write(data, to: draftURL(ownerUserID: ownerUserID, roundID: roundID))
        }
    }

    func beginDraftSave(ownerUserID: UUID, roundID: UUID) -> Int {
        lock.withLock {
            invalidatePublication(ownerUserID: ownerUserID, roundID: roundID)
            return draftTickets.next(ownerUserID, roundID)
        }
    }

    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID, ticket: Int) {
        lock.withLock {
            guard draftTickets.isCurrent(ticket, ownerUserID, roundID) else { return }
            write(data, to: draftURL(ownerUserID: ownerUserID, roundID: roundID))
        }
    }

    func removeDraft(ownerUserID: UUID, roundID: UUID) {
        lock.withLock {
            invalidatePublication(ownerUserID: ownerUserID, roundID: roundID)
            _ = draftTickets.next(ownerUserID, roundID)
            try? FileManager.default.removeItem(at: draftURL(ownerUserID: ownerUserID, roundID: roundID))
        }
    }

    func markDraftForPublication(ownerUserID: UUID, roundID: UUID) throws -> UUID {
        try lock.withLock {
            let id = draftTickets.markPublication(ownerUserID, roundID)
            let url = publicationURL(ownerUserID: ownerUserID, roundID: roundID)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(id).write(to: url, options: .atomic)
            return id
        }
    }

    func removePublishedDraft(_ publication: GameDrawingDraftPublication, ownerUserID: UUID,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws -> Bool {
        try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            try lock.withLock {
                let markerURL = publicationURL(ownerUserID: ownerUserID, roundID: publication.roundID)
                guard let id = publication.id,
                      draftTickets.canRemovePersistedPublication(id, ownerUserID, publication.roundID),
                      let marker = try? Data(contentsOf: markerURL),
                      try JSONDecoder().decode(UUID.self, from: marker) == id else { return false }
                let drawingURL = draftURL(ownerUserID: ownerUserID, roundID: publication.roundID)
                guard FileManager.default.fileExists(atPath: drawingURL.path),
                      try Data(contentsOf: drawingURL) == publication.data else { return false }
                let descriptionURL = draftDescriptionURL(ownerUserID: ownerUserID, roundID: publication.roundID)
                let hasDescription = FileManager.default.fileExists(atPath: descriptionURL.path)
                var text: String?
                if hasDescription {
                    let saved = try JSONDecoder().decode(
                        GameDrawingDescriptionDraft.self, from: Data(contentsOf: descriptionURL)
                    )
                    guard saved.coupleID == publication.coupleID else { return false }
                    text = saved.text.trimmedNonEmpty
                }
                guard text == publication.accessibilityText?.trimmedNonEmpty else { return false }
                _ = draftTickets.next(ownerUserID, publication.roundID)
                try FileManager.default.removeItem(at: drawingURL)
                if hasDescription { try FileManager.default.removeItem(at: descriptionURL) }
                try FileManager.default.removeItem(at: markerURL)
                return true
            }
        }
    }

    func draftDescription(ownerUserID: UUID, coupleID: UUID, roundID: UUID?) throws -> String? {
        try lock.withLock {
            let url = draftDescriptionURL(ownerUserID: ownerUserID, roundID: roundID)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let saved = try JSONDecoder().decode(GameDrawingDescriptionDraft.self, from: Data(contentsOf: url))
            return saved.coupleID == coupleID ? saved.text : nil
        }
    }

    func saveDraftDescription(_ text: String, ownerUserID: UUID, coupleID: UUID, roundID: UUID?,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws {
        try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            try lock.withLock {
                if let roundID { invalidatePublication(ownerUserID: ownerUserID, roundID: roundID) }
                let url = draftDescriptionURL(ownerUserID: ownerUserID, roundID: roundID)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try JSONEncoder().encode(GameDrawingDescriptionDraft(coupleID: coupleID, text: text))
                    .write(to: url, options: .atomic)
            }
        }
    }

    func removeDraftDescription(ownerUserID: UUID, roundID: UUID?) {
        lock.withLock {
            if let roundID { invalidatePublication(ownerUserID: ownerUserID, roundID: roundID) }
            try? FileManager.default.removeItem(at: draftDescriptionURL(ownerUserID: ownerUserID, roundID: roundID))
        }
    }

    func moveDraftDescription(ownerUserID: UUID, from: UUID?, to: UUID?,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws {
        try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            try lock.withLock {
                if let from { invalidatePublication(ownerUserID: ownerUserID, roundID: from) }
                if let to { invalidatePublication(ownerUserID: ownerUserID, roundID: to) }
                let source = draftDescriptionURL(ownerUserID: ownerUserID, roundID: from)
                guard FileManager.default.fileExists(atPath: source.path) else { return }
                let destination = draftDescriptionURL(ownerUserID: ownerUserID, roundID: to)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data(contentsOf: source).write(to: destination, options: .atomic)
                try FileManager.default.removeItem(at: source)
            }
        }
    }

    private func publicationURL(ownerUserID: UUID, roundID: UUID) -> URL {
        draftURL(ownerUserID: ownerUserID, roundID: roundID).appendingPathExtension("publication.json")
    }

    private func invalidatePublication(ownerUserID: UUID, roundID: UUID) {
        try? FileManager.default.removeItem(at: publicationURL(ownerUserID: ownerUserID, roundID: roundID))
    }

    private func draftDescriptionURL(ownerUserID: UUID, roundID: UUID?) -> URL {
        let drawingURL = roundID.map { draftURL(ownerUserID: ownerUserID, roundID: $0) }
            ?? rescuedURL(ownerUserID: ownerUserID)
        return drawingURL.appendingPathExtension("description.json")
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

    func liveSnapshot(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { try? Data(contentsOf: snapshotURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func saveLiveSnapshot(_ data: Data, ownerUserID: UUID, roundID: UUID) {
        lock.withLock {
            let url = snapshotURL(ownerUserID: ownerUserID, roundID: roundID)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            write(data, to: url)
        }
    }

    func removeLiveSnapshot(ownerUserID: UUID, roundID: UUID) {
        lock.withLock {
            try? FileManager.default.removeItem(at: snapshotURL(ownerUserID: ownerUserID, roundID: roundID))
        }
    }

    func clearDownloads() {
        lock.withLock {
            for folder in ["downloads", "snapshots"] {
                try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(folder, isDirectory: true))
            }
        }
    }

    func clearAll() {
        lock.withLock {
            draftTickets.invalidateAll()
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

    private func snapshotURL(ownerUserID: UUID, roundID: UUID) -> URL {
        directoryURL
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(roundID.uuidString.lowercased() + ".pkdrawing", isDirectory: false)
    }

    private func downloadURL(mediaAssetID: UUID) -> URL {
        directoryURL
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(mediaAssetID.uuidString.lowercased() + ".pkdrawing", isDirectory: false)
    }
}

nonisolated struct GameDrawingDescriptionDraft: Codable {
    let coupleID: UUID
    let text: String
}

/// The exact draft content accepted by the server. A late response cannot remove a newer draft.
nonisolated struct GameDrawingDraftPublication: Sendable {
    let id: UUID?
    let coupleID: UUID
    let roundID: UUID
    let data: Data
    let accessibilityText: String?
}
