import PencilKit
import SwiftUI

/// A finished drawing, all of it, on a canvas that takes no touches.
struct GameStaticDrawing: UIViewRepresentable {
    let drawing: PKDrawing

    func makeUIView(context _: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        canvasView.isUserInteractionEnabled = false
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context _: Context) {
        canvasView.drawing = drawing
    }
}
