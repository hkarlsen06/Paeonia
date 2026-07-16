import PencilKit
import UIKit

nonisolated protocol WidgetDrawingRasterizing: Sendable {
    @MainActor
    func renderPNG(
        fromDrawingData: Data,
        canvasSide: CGFloat,
        pixelWidth: CGFloat
    ) async -> Data?
}

/// Renders a saved drawing into the raster previews the widget displays.
///
/// Previews are derived cache data, not the canonical drawing. Rendering uses a
/// light interface style so the literal ink colors match what the in-app canvas
/// shows, and a transparent background so the strokes composite over the
/// widget's plum container (and tint correctly in accessibility tinted mode).
///
/// Works in terms of `Data` in and `Data` out (both `Sendable`) and runs on the
/// main actor, so the canvas service actor can call it without passing
/// non-`Sendable` PencilKit/UIKit values across an isolation boundary.
nonisolated struct WidgetDrawingRasterizer: WidgetDrawingRasterizing {
    /// Decodes `drawingData` and renders a PNG whose long edge is roughly
    /// `pixelWidth` pixels wide.
    ///
    /// - Parameters:
    ///   - drawingData: The canonical `PKDrawing.dataRepresentation()` payload.
    ///   - canvasSide: The point side length of the square canvas the strokes
    ///     were drawn in. Strokes are stored in this coordinate space.
    ///   - pixelWidth: The target rendered width in pixels.
    @MainActor
    // Async protocol shape lets the save coordinator test and guard actor
    // reentrancy around rendering; UIKit itself completes synchronously here.
    func renderPNG(
        fromDrawingData drawingData: Data,
        canvasSide: CGFloat,
        pixelWidth: CGFloat
    ) async -> Data? {
        await Task.yield()
        guard canvasSide > 0,
              pixelWidth > 0,
              let drawing = try? PKDrawing(data: drawingData)
        else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide)
        let scale = max(1, pixelWidth / canvasSide)

        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image?.pngData()
    }
}
