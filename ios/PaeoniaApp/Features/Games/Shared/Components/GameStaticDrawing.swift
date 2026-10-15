import PencilKit
import SwiftUI

/// A finished drawing, all of it, on a canvas that takes no touches. The
/// drawing is at the canonical size and is scaled to `side` here, once, and
/// again only when the drawing or the size changes. Setting a drawing makes
/// PencilKit draw all of it again, and SwiftUI updates this view far more often
/// than it changes.
struct GameStaticDrawing: UIViewRepresentable {
    let drawing: PKDrawing
    /// The canvas size in points.
    let side: CGFloat

    func makeUIView(context _: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        canvasView.isUserInteractionEnabled = false
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.show(drawing, side: side, on: canvasView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var shown: (fingerprint: Int, side: CGFloat)?

        func show(_ drawing: PKDrawing, side: CGFloat, on canvasView: PKCanvasView) {
            let fingerprint = Self.fingerprint(of: drawing)
            guard shown?.fingerprint != fingerprint || shown?.side != side else {
                return
            }
            shown = (fingerprint, side)
            canvasView.drawing = GameCanvas.fitted(drawing, toSide: side)
        }

        /// Changes when a stroke is added, removed, erased into or moved. Cheaper
        /// than comparing the encoded drawings.
        private static func fingerprint(of drawing: PKDrawing) -> Int {
            var hasher = Hasher()
            for stroke in drawing.strokes {
                hasher.combine(stroke.path.creationDate)
                hasher.combine(stroke.path.count)
                hasher.combine(stroke.randomSeed)
                hasher.combine(WidgetLiveStrokeSync.signature(for: stroke))
            }
            return hasher.finalize()
        }
    }
}
