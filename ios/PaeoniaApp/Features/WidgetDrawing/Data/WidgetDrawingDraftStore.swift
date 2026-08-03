import Foundation

/// Owner-scoped local storage for an unfinished PencilKit drawing. The bytes
/// remain the canonical `PKDrawing.dataRepresentation()` so restoring a draft
/// does not introduce a second stroke format.
@MainActor
protocol WidgetDrawingDraftStoring: AnyObject {
    func draft(for ownerUserID: UUID) -> Data?
    func setDraft(_ data: Data, for ownerUserID: UUID)
    func clearDraft(for ownerUserID: UUID)
}

@MainActor
final class FileWidgetDrawingDraftStore: WidgetDrawingDraftStoring {
    static let shared = FileWidgetDrawingDraftStore()

    private let directoryURL: URL

    init(directoryURL: URL = FileWidgetDrawingDraftStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    func draft(for ownerUserID: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: ownerUserID))
    }

    func setDraft(_ data: Data, for ownerUserID: UUID) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL(for: ownerUserID), options: .atomic)
        } catch {
            // Draft persistence is best-effort. The active PencilKit canvas
            // remains the source of truth for the current session.
        }
    }

    func clearDraft(for ownerUserID: UUID) {
        let url = fileURL(for: ownerUserID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
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
