import PencilKit
import UIKit

extension WidgetDrawingViewModel {
    /// What the share sheet offers for the drawing on the canvas, sent or not: the
    /// ink on its plum canvas. Nil while the canvas is empty.
    var shareable: PaeoniaShareable? {
        guard !drawing.strokes.isEmpty else { return nil }
        let drawing = drawing
        let side = currentCanvasSide()
        return PaeoniaShareable(title: String(localized: .shareTitleDrawing)) {
            guard let ink = PaeoniaShareRenderer.inkImage(of: drawing, canvasSide: side) else { return nil }
            return PaeoniaShareCards.drawing(ink: ink)
        }
    }

    /// The drawing on the canvas as the widget shows it, for a picture of the widget.
    /// Nil while the canvas is empty.
    var widgetImage: UIImage? {
        let side = drawingCanvasSide ?? laidOutCanvasSide ?? Self.fallbackCanvasSide
        guard side > 0, !drawing.strokes.isEmpty else {
            return nil
        }
        var image: UIImage?
        // Light, like the widget's own previews, so the ink colors match.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: 2)
        }
        return image
    }
}
