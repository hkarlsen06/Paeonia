import CoreGraphics
import CryptoKit
import Foundation

nonisolated func writeLine(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

nonisolated enum PaeoniaAppGroup { static let identifier = "WidgetPendingInstanceRepro" }
nonisolated extension SHA256.Digest {
    var paeoniaHexString: String { map { String(format: "%02x", $0) }.joined() }
}
nonisolated struct WidgetUploadProgress: Codable, Equatable, Sendable { let revisionID: UUID }
nonisolated struct WidgetDrawingUploadPayload: Sendable {
    let drawingData: Data
    let canvasSide: CGFloat
    let strokeCount: Int
    let pointCount: Int
    let bounds: CGRect
    let accessibilityText: String?
    var publicationID: String {
        WidgetDrawingPublication.id(drawingData: drawingData, canvasSide: Double(canvasSide),
                                    accessibilityText: accessibilityText)
    }
}
@main struct PendingInstanceRepro {
    static func main() {
        let name = "WidgetPendingInstanceRepro-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        let store = WidgetPendingUploadStore(defaults: defaults)
        let first = WidgetDrawingUploadPayload(drawingData: Data([1,2]), canvasSide: 320,
                                               strokeCount: 1, pointCount: 2, bounds: .zero,
                                               accessibilityText: "A sun")
        let second = WidgetDrawingUploadPayload(drawingData: first.drawingData, canvasSide: first.canvasSide,
                                                strokeCount: 1, pointCount: 2, bounds: .zero,
                                                accessibilityText: first.accessibilityText)
        store.markPending(first, contentHash: SHA256.hash(data: first.drawingData).paeoniaHexString)
        let oldID = first.publicationID
        store.clearAll()
        store.markPending(second, contentHash: SHA256.hash(data: first.drawingData).paeoniaHexString)
        let oldProgress = WidgetUploadProgress(revisionID: UUID())
        store.saveProgress(oldProgress, publicationID: oldID)
        writeLine("Distinct user publications received equal IDs: \(oldID == second.publicationID)")
        writeLine("Old upload progress entered the post-purge marker: \(store.pendingSnapshot?.progress == oldProgress)")
    }
}
