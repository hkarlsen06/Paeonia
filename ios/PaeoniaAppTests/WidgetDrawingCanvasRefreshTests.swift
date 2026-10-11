import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// The pixel eraser can change the canvas without a change callback.
@MainActor
struct WidgetDrawingCanvasRefreshTests {
    @Test func picksUpACanvasChangeThatHadNoCallback() {
        let viewModel = WidgetDrawingViewModel()
        let canvasView = PKCanvasView()
        viewModel.bindCanvasView(canvasView)
        viewModel.canvasDidApplyDrawing(revision: 0)

        let erased = PKDrawing(strokes: [makeRefreshStroke()])
        canvasView.drawing = erased
        viewModel.refreshDrawingFromCanvas()

        #expect(viewModel.drawing == erased)
        #expect(viewModel.hasUnsavedEdits)
    }

    @Test func ignoresTheCanvasUntilItShowsTheLatestReplace() {
        let viewModel = WidgetDrawingViewModel()
        let canvasView = PKCanvasView()
        viewModel.bindCanvasView(canvasView)
        viewModel.canvasDidApplyDrawing(revision: 0)
        canvasView.drawing = PKDrawing(strokes: [makeRefreshStroke()])

        // Clearing replaces the drawing from code. The canvas view still shows
        // the old strokes until SwiftUI updates it, so they must not come back.
        viewModel.clearCanvas()
        viewModel.refreshDrawingFromCanvas()

        #expect(viewModel.drawing.strokes.isEmpty)
    }
}

@MainActor
private func makeRefreshStroke() -> PKStroke {
    let points = (0..<3).map { index in
        PKStrokePoint(
            location: CGPoint(x: 10 + CGFloat(index) * 10, y: 20),
            timeOffset: Double(index) * 0.01,
            size: CGSize(width: 4, height: 4),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2
        )
    }
    return PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))
}
