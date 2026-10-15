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
///
/// `Sendable` because a background task writes drafts through it
/// (`setDraft(_:base:for:)`). Main-actor classes are `Sendable` already.
@MainActor
protocol WidgetDrawingDraftStoring: AnyObject, Sendable {
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
    /// (`PKDrawing.paeoniaStrokeFingerprint`). Nil when the best-effort write failed.
    func draftBase(for key: WidgetDrawingDraftKey) -> String?
    func setDraftBase(_ fingerprint: String, for key: WidgetDrawingDraftKey)
    /// Writes a draft and the base it was made on from a background task, where
    /// the main actor is not available.
    nonisolated func setDraft(_ data: Data, base fingerprint: String, for key: WidgetDrawingDraftKey)
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
        try? Data(contentsOf: fileURL(for: key))
    }

    func setDraft(_ data: Data, for key: WidgetDrawingDraftKey) {
        writeDraft(data, for: key)
    }

    nonisolated func setDraft(_ data: Data, base fingerprint: String, for key: WidgetDrawingDraftKey) {
        writeDraft(data, for: key)
        try? Data(fingerprint.utf8).write(to: baseFileURL(for: key), options: .atomic)
    }

    nonisolated private func writeDraft(_ data: Data, for key: WidgetDrawingDraftKey) {
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

    nonisolated private func baseFileURL(for key: WidgetDrawingDraftKey) -> URL {
        fileURL(for: key).deletingPathExtension().appendingPathExtension("base")
    }

    func clearDraft(for ownerUserID: UUID) {
        purgeGenerations[ownerUserID, default: 0] += 1
        try? FileManager.default.removeItem(at: ownerDirectoryURL(for: ownerUserID))
    }

    func purgeGeneration(for ownerUserID: UUID) -> Int {
        purgeGenerations[ownerUserID, default: 0]
    }

    nonisolated private func ownerDirectoryURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
    }

    nonisolated private func fileURL(for key: WidgetDrawingDraftKey) -> URL {
        let suffix = key.slot == .setAside ? "-set-aside" : ""
        return ownerDirectoryURL(for: key.ownerUserID).appendingPathComponent(
            "\(key.coupleID.uuidString.lowercased())\(suffix).drawing",
            isDirectory: false
        )
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WidgetDrawingDrafts", isDirectory: true)
    }
}
