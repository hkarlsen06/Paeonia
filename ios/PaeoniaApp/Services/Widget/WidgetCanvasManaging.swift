import CoreGraphics
import Foundation

/// The last saved drawing plus its on-canvas attribution: who saved it and when.
/// `authorName`/`createdAt` are nil when no matching saved metadata is available.
nonisolated struct WidgetCanvasSnapshot: Sendable, Equatable {
    let drawingData: Data
    let authorName: String?
    let createdAt: Date?
    /// Side of the square canvas the strokes were drawn on, when known. A
    /// drawing from a phone with a different screen size is scaled by this.
    var canvasSide: CGFloat?
}

nonisolated protocol WidgetCanvasManaging: Sendable {
    /// Returns the canonical data for the last saved drawing, if one exists and
    /// still decodes.
    func loadSavedDrawing() async -> Data?

    /// Returns the last saved drawing together with its attribution (author name
    /// and save time) for display on the canvas. Defaults to the canonical
    /// drawing with no attribution; `WidgetCanvasService` fills in the metadata.
    func loadSavedSnapshot() async -> WidgetCanvasSnapshot?

    /// Persists the drawing locally, renders widget previews, updates the App
    /// Group payload, and reloads the widget. `authorName` is the display name
    /// of whoever saved the drawing, and `createdAt` is when it was drawn (the
    /// author's save time for synced revisions), both shown on the widget.
    func saveDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date
    ) async throws

    /// Shows a partner's drawing that came from the server. `revisionID` is the
    /// server's revision, so the widget can tell it already has this drawing.
    func saveSyncedDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date,
        revisionID: UUID
    ) async throws

    /// Removes the saved drawing and widget previews so private content does not
    /// linger on the Home Screen after a session ends.
    func clearForPrivacy() async

    /// Hides widget-visible derivatives while preserving the canonical drawing
    /// for a temporary entitlement loss.
    func hideForPrivacy() async

    /// True while the widget files exist and the app can read them.
    /// `hideForPrivacy` removes them and keeps the saved drawing, so sync must
    /// publish the drawing again.
    func isShowingSavedDrawing() async -> Bool
}

extension WidgetCanvasManaging {
    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        guard let data = await loadSavedDrawing() else {
            return nil
        }
        return WidgetCanvasSnapshot(drawingData: data, authorName: nil, createdAt: nil)
    }

    func hideForPrivacy() async {
        await clearForPrivacy()
    }

    func isShowingSavedDrawing() -> Bool {
        true
    }

    func saveSyncedDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date,
        revisionID _: UUID
    ) async throws {
        try await saveDrawing(drawingData, canvasSize: canvasSize, authorName: authorName, createdAt: createdAt)
    }
}
