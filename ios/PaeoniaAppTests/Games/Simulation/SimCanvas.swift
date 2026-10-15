import Foundation
import PencilKit
@testable import PaeoniaApp

/// The drawer's PencilKit canvas on screen, standing in for `PencilKitCanvasView`.
/// It applies drawings the board replaced from code, as `updateUIView` does, and
/// reports strokes drawn on it the way the canvas delegate does.
@MainActor
final class SimCanvas {
    let view: PKCanvasView
    let side: CGFloat
    private let board: GameDrawingBoard
    private var appliedRevision = -1

    init(viewModel: DrawAndGuessViewModel, side: CGFloat) {
        self.side = side
        board = viewModel.board
        view = PKCanvasView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        sync()
        viewModel.canvasReady(view)
        board.canvasDidLayout(side: side)
        sync()
    }

    /// SwiftUI's update pass.
    func sync() {
        guard appliedRevision != board.drawingRevision else { return }
        view.drawing = board.drawing
        appliedRevision = board.drawingRevision
        board.canvasDidApplyDrawing(revision: appliedRevision)
    }

    func draw(_ stroke: PKStroke) {
        sync()
        board.setStrokeInProgress(true)
        let drawing = PKDrawing(strokes: view.drawing.strokes + [stroke])
        view.drawing = drawing
        board.updateDrawing(drawing)
        board.setStrokeInProgress(false)
    }

    func erase(strokeAt index: Int) {
        sync()
        var strokes = view.drawing.strokes
        guard strokes.indices.contains(index) else { return }
        strokes.remove(at: index)
        let drawing = PKDrawing(strokes: strokes)
        view.drawing = drawing
        board.updateDrawing(drawing)
    }
}
