import PencilKit

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
}
