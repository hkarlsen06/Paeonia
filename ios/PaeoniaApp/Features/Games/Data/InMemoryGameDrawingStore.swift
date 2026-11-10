import Foundation

/// For tests and the developer scenarios.
nonisolated final class InMemoryGameDrawingStore: GameDrawingStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var drafts: [String: Data] = [:]
    private var draftTickets = GameDraftTickets()
    private var startedBackgroundSaves = 0
    private var finishedBackgroundSaves = 0
    private var descriptions: [String: GameDrawingDescriptionDraft] = [:]
    private var descriptionReadFailures: Int
    private var rescued: [UUID: Data] = [:]
    private var downloads: [UUID: Data] = [:]
    private var snapshots: [UUID: (roundID: UUID, data: Data)] = [:]

    init(descriptionReadFailures: Int = 0) {
        self.descriptionReadFailures = descriptionReadFailures
    }

    func draft(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { drafts["\(ownerUserID)/\(roundID)"] }
    }

    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID) {
        lock.withLock {
            _ = draftTickets.next(ownerUserID, roundID)
            drafts["\(ownerUserID)/\(roundID)"] = data
        }
    }

    func beginDraftSave(ownerUserID: UUID, roundID: UUID) -> Int {
        lock.withLock {
            startedBackgroundSaves += 1
            return draftTickets.next(ownerUserID, roundID)
        }
    }

    /// Whether a background draft save has begun and not written yet. Tests wait for
    /// this to be false before they read a draft or close the app.
    var hasUnfinishedBackgroundSave: Bool {
        lock.withLock { startedBackgroundSaves != finishedBackgroundSaves }
    }

    func saveDraft(_ data: Data, ownerUserID: UUID, roundID: UUID, ticket: Int) {
        lock.withLock {
            finishedBackgroundSaves += 1
            guard draftTickets.isCurrent(ticket, ownerUserID, roundID) else { return }
            drafts["\(ownerUserID)/\(roundID)"] = data
        }
    }

    func removeDraft(ownerUserID: UUID, roundID: UUID) {
        lock.withLock {
            _ = draftTickets.next(ownerUserID, roundID)
            drafts["\(ownerUserID)/\(roundID)"] = nil
        }
    }

    func markDraftForPublication(ownerUserID: UUID, roundID: UUID) -> UUID {
        lock.withLock { draftTickets.markPublication(ownerUserID, roundID) }
    }

    func removePublishedDraft(_ publication: GameDrawingDraftPublication, ownerUserID: UUID,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws -> Bool {
        try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            lock.withLock {
                guard let id = publication.id,
                      draftTickets.isCurrentPublication(id, ownerUserID, publication.roundID) else { return false }
                let key = "\(ownerUserID)/\(publication.roundID)"
                guard drafts[key] == publication.data else { return false }
                let saved = descriptions[key]
                guard saved == nil || saved?.coupleID == publication.coupleID,
                      saved?.text.trimmedNonEmpty == publication.accessibilityText?.trimmedNonEmpty
                else { return false }
                _ = draftTickets.next(ownerUserID, publication.roundID)
                drafts[key] = nil
                descriptions[key] = nil
                return true
            }
        }
    }

    func draftDescription(ownerUserID: UUID, coupleID: UUID, roundID: UUID?) throws -> String? {
        try lock.withLock {
            if descriptionReadFailures > 0 {
                descriptionReadFailures -= 1
                throw CocoaError(.fileReadUnknown)
            }
            guard let draft = descriptions["\(ownerUserID)/\(roundID?.uuidString ?? "rescued")"],
                  draft.coupleID == coupleID else { return nil }
            return draft.text
        }
    }

    func saveDraftDescription(_ text: String, ownerUserID: UUID, coupleID: UUID, roundID: UUID?,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws {
        try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            lock.withLock {
                let key = "\(ownerUserID)/\(roundID?.uuidString ?? "rescued")"
                descriptions[key] = GameDrawingDescriptionDraft(coupleID: coupleID, text: text)
            }
        }
    }

    func moveDraftDescription(ownerUserID: UUID, from: UUID?, to: UUID?,
                              privacyToken: LocalPrivacyWriteGuard.Token) throws {
        try LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            lock.withLock {
                let key = "\(ownerUserID)/\(from?.uuidString ?? "rescued")"
                descriptions["\(ownerUserID)/\(to?.uuidString ?? "rescued")"] = descriptions[key]
                descriptions[key] = nil
            }
        }
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

    func liveSnapshot(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { snapshots[ownerUserID].flatMap { $0.roundID == roundID ? $0.data : nil } }
    }

    func saveLiveSnapshot(_ data: Data, ownerUserID: UUID, roundID: UUID) {
        lock.withLock { snapshots[ownerUserID] = (roundID, data) }
    }

    func removeLiveSnapshot(ownerUserID: UUID, roundID: UUID) {
        lock.withLock {
            if snapshots[ownerUserID]?.roundID == roundID {
                snapshots[ownerUserID] = nil
            }
        }
    }

    func clearDownloads() {
        lock.withLock {
            downloads = [:]
            snapshots = [:]
        }
    }

    func clearAll() {
        lock.withLock {
            draftTickets.invalidateAll()
            drafts = [:]
            descriptions = [:]
            rescued = [:]
            downloads = [:]
            snapshots = [:]
        }
    }
}
