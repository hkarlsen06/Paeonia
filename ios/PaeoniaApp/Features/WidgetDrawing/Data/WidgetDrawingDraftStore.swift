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
protocol WidgetDrawingDraftStoring: AnyObject, Sendable {
    func saveDraft(_ data: Data, base: String, description: String, for key: WidgetDrawingDraftKey) throws
    func hasRetainedDraft(for key: WidgetDrawingDraftKey) -> Bool
    func description(for key: WidgetDrawingDraftKey) -> String?
    func draft(for key: WidgetDrawingDraftKey) -> Data?
    func removeDraft(for key: WidgetDrawingDraftKey)
    func clearDraft(for ownerUserID: UUID)
    func purgeGeneration(for ownerUserID: UUID) -> Int
    func draftBase(for key: WidgetDrawingDraftKey) -> String?
}

@MainActor
final class FileWidgetDrawingDraftStore: WidgetDrawingDraftStoring {
    static let shared = FileWidgetDrawingDraftStore()

    private let directoryURL: URL
    private var purgeGenerations: [UUID: Int] = [:]
    private struct RetainedDraft: Codable {
        let data: Data
        let base: String
        let description: String
    }
    private var retainedDrafts: [WidgetDrawingDraftKey: RetainedDraft] = [:]

    func hasRetainedDraft(for key: WidgetDrawingDraftKey) -> Bool { retainedDrafts[key] != nil }

    func saveDraft(_ data: Data, base: String, description: String, for key: WidgetDrawingDraftKey) throws {
        // Keep all fields together until the file is safe. This copy also survives
        // closing the canvas, and the existing privacy purge removes it.
        let snapshot = RetainedDraft(data: data, base: base, description: description)
        retainedDrafts[key] = snapshot
        try FileManager.default.createDirectory(
            at: ownerDirectoryURL(for: key.ownerUserID), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: fileURL(for: key), options: .atomic)
        retainedDrafts[key] = nil
    }

    init(directoryURL: URL = FileWidgetDrawingDraftStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    private func snapshot(for key: WidgetDrawingDraftKey) -> RetainedDraft? {
        if let retained = retainedDrafts[key] { return retained }
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? JSONDecoder().decode(RetainedDraft.self, from: data)
    }

    func description(for key: WidgetDrawingDraftKey) -> String? { snapshot(for: key)?.description }
    func draft(for key: WidgetDrawingDraftKey) -> Data? { snapshot(for: key)?.data }
    func draftBase(for key: WidgetDrawingDraftKey) -> String? { snapshot(for: key)?.base }

    func removeDraft(for key: WidgetDrawingDraftKey) {
        retainedDrafts[key] = nil
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func clearDraft(for ownerUserID: UUID) {
        purgeGenerations[ownerUserID, default: 0] += 1
        retainedDrafts = retainedDrafts.filter { $0.key.ownerUserID != ownerUserID }
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
