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
    var accessibilityText: String?
}

/// The publication and privacy state before its upload starts. A late response
/// cannot attach a server revision to a newer local drawing or a new session.
nonisolated struct WidgetCanvasPublicationTicket: Sendable {
    let publicationID: UUID
    let generations: WidgetCanvasGenerations
    let privacyEpoch: Int
}

nonisolated protocol WidgetCanvasManaging: Sendable {
    /// Returns the canonical data for the last saved drawing, if one exists and
    /// still decodes.
    func loadSavedDrawing() async -> Data?

    /// Returns the last saved drawing together with its attribution (author name
    /// and save time) for display on the canvas. Defaults to the canonical
    /// drawing with no attribution; `WidgetCanvasService` fills in the metadata.
    func loadSavedSnapshot() async -> WidgetCanvasSnapshot?

    func saveDescribedDrawing(
        _ drawingData: Data, canvasSize: CGSize, authorName: String?, createdAt: Date,
        revisionID: UUID?, accessibilityText: String?, publicationID: UUID?
    ) async throws

    func capturePublicationTicket(for payload: WidgetDrawingUploadPayload) async -> WidgetCanvasPublicationTicket

    func acceptPublication(_ ticket: WidgetCanvasPublicationTicket, revisionID: UUID) async throws

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
}
