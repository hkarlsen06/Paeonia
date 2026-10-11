import Foundation

/// One unfinished drawing per person and relationship. Keying by couple means a
/// draft that holds an ex-partner's strokes is never shown to a new couple.
nonisolated struct WidgetDrawingDraftKey: Hashable, Sendable {
    enum Slot: Hashable, Sendable {
        /// What is on the canvas and not sent yet.
        case canvas
        /// Unsent work that a new drawing from the partner replaced on the
        /// canvas. Kept until the person brings it back or deletes it.
        case setAside
    }

    let ownerUserID: UUID
    let coupleID: UUID
    var slot: Slot = .canvas
}

/// Local storage for an unfinished PencilKit drawing. The bytes remain the
/// canonical `PKDrawing.dataRepresentation()` so restoring a draft does not
/// introduce a second stroke format.
@MainActor
protocol WidgetDrawingDraftStoring: AnyObject {
    func draft(for key: WidgetDrawingDraftKey) -> Data?
    func setDraft(_ data: Data, for key: WidgetDrawingDraftKey)
    func removeDraft(for key: WidgetDrawingDraftKey)
    /// Removes every draft of one person, for all relationships. The privacy
    /// purge calls this.
    func clearDraft(for ownerUserID: UUID)
    /// Goes up each time `clearDraft(for:)` runs for this person. A drawing
    /// screen that was open before a purge compares it and stops saving drafts.
    func purgeGeneration(for ownerUserID: UUID) -> Int
    /// Names the drawing that was on the widgets when the draft was made
    /// (`PKDrawing.paeoniaStrokeFingerprint`). Nil for drafts from older builds.
    func draftBase(for key: WidgetDrawingDraftKey) -> String?
    func setDraftBase(_ fingerprint: String, for key: WidgetDrawingDraftKey)
}

extension WidgetDrawingDraftStoring {
    func draftBase(for _: WidgetDrawingDraftKey) -> String? { nil }
    func setDraftBase(_: String, for _: WidgetDrawingDraftKey) {}
}

@MainActor
final class FileWidgetDrawingDraftStore: WidgetDrawingDraftStoring {
    static let shared = FileWidgetDrawingDraftStore()

    private let directoryURL: URL
    private var purgeGenerations: [UUID: Int] = [:]

    init(directoryURL: URL = FileWidgetDrawingDraftStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    func draft(for key: WidgetDrawingDraftKey) -> Data? {
        if let data = try? Data(contentsOf: fileURL(for: key)) {
            return data
        }
        return key.slot == .canvas ? moveLegacyDraft(to: key) : nil
    }

    /// Builds before drafts were kept per relationship stored one file per
    /// person. The privacy purge deletes that file on unpair, so one that still
    /// exists belongs to the current couple. Move it there instead of dropping
    /// the unsent drawing. If the move fails the file stays and is read again.
    private func moveLegacyDraft(to key: WidgetDrawingDraftKey) -> Data? {
        let legacyURL = legacyFileURL(for: key.ownerUserID)
        guard let data = try? Data(contentsOf: legacyURL) else {
            return nil
        }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: ownerDirectoryURL(for: key.ownerUserID),
            withIntermediateDirectories: true
        )
        try? fileManager.moveItem(at: legacyURL, to: fileURL(for: key))
        return data
    }

    func setDraft(_ data: Data, for key: WidgetDrawingDraftKey) {
        do {
            try FileManager.default.createDirectory(
                at: ownerDirectoryURL(for: key.ownerUserID),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Draft persistence is best-effort. The active PencilKit canvas
            // remains the source of truth for the current session.
        }
    }

    func removeDraft(for key: WidgetDrawingDraftKey) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
        try? FileManager.default.removeItem(at: baseFileURL(for: key))
    }

    func draftBase(for key: WidgetDrawingDraftKey) -> String? {
        (try? Data(contentsOf: baseFileURL(for: key))).flatMap { String(data: $0, encoding: .utf8) }
    }

    func setDraftBase(_ fingerprint: String, for key: WidgetDrawingDraftKey) {
        try? Data(fingerprint.utf8).write(to: baseFileURL(for: key), options: .atomic)
    }

    private func baseFileURL(for key: WidgetDrawingDraftKey) -> URL {
        fileURL(for: key).deletingPathExtension().appendingPathExtension("base")
    }

    func clearDraft(for ownerUserID: UUID) {
        purgeGenerations[ownerUserID, default: 0] += 1
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: ownerDirectoryURL(for: ownerUserID))
        // The one-file-per-person draft from older builds goes too. Because of
        // this, a legacy file that still exists belongs to the current couple,
        // which is what makes `moveLegacyDraft` safe.
        try? fileManager.removeItem(at: legacyFileURL(for: ownerUserID))
    }

    func purgeGeneration(for ownerUserID: UUID) -> Int {
        purgeGenerations[ownerUserID, default: 0]
    }

    private func ownerDirectoryURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
    }

    private func fileURL(for key: WidgetDrawingDraftKey) -> URL {
        let suffix = key.slot == .setAside ? "-set-aside" : ""
        return ownerDirectoryURL(for: key.ownerUserID).appendingPathComponent(
            "\(key.coupleID.uuidString.lowercased())\(suffix).drawing",
            isDirectory: false
        )
    }

    private func legacyFileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(ownerUserID.uuidString.lowercased()).drawing",
            isDirectory: false
        )
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WidgetDrawingDrafts", isDirectory: true)
    }
}
