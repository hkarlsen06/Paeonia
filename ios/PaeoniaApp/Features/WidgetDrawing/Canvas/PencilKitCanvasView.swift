import PencilKit
import SwiftUI

struct PencilKitCanvasView: UIViewRepresentable {
    let drawing: PKDrawing
    /// Changes only when the view model replaced the drawing from code. Strokes
    /// drawn on the canvas never change it, so they are not pushed back in.
    let drawingRevision: Int
    let tool: CanvasTool
    let onCanvasReady: (PKCanvasView) -> Void
    let onDrawingChange: (PKDrawing) -> Void
    let onStrokeInProgressChange: (Bool) -> Void
    /// A tap with the paint bucket, in canvas points.
    var onFill: (CGPoint) -> Void = { _ in }
    /// The canvas now shows the drawing of this `drawingRevision`.
    var onDrawingApplied: (Int) -> Void = { _ in }
    /// The canvas finished rendering. The pixel eraser can change the drawing
    /// without `canvasViewDrawingDidChange`, so this is a moment to read it again.
    var onFinishRendering: () -> Void = {}
    /// Points of canvas above the drawing's top edge. The view is that much taller
    /// than the drawing area, and strokes drawn there have a negative y.
    var overscanTop: CGFloat = 0

    func makeUIView(context: Context) -> PaeoniaDrawingCanvasContainer {
        let container = PaeoniaDrawingCanvasContainer()
        let canvasView = container.canvas
        canvasView.overscanTop = overscanTop
        canvasView.canvasTool = tool
        let coordinator = context.coordinator
        canvasView.onFill = { [weak coordinator] point in
            coordinator?.parent.onFill(point)
        }
        canvasView.onInkStrokeInProgressChange = { [weak coordinator] inProgress in
            coordinator?.parent.onStrokeInProgressChange(inProgress)
        }
        // Assign the initial drawing before wiring the delegate so this
        // programmatic assignment can't bounce back through
        // `canvasViewDrawingDidChange` while SwiftUI is still building the view.
        canvasView.drawing = drawing
        coordinator.appliedDrawingRevision = drawingRevision
        onDrawingApplied(drawingRevision)
        canvasView.delegate = coordinator
        onCanvasReady(canvasView)
        return container
    }

    func updateUIView(_ container: PaeoniaDrawingCanvasContainer, context: Context) {
        let canvasView = container.canvas
        context.coordinator.parent = self
        canvasView.overscanTop = overscanTop
        canvasView.canvasTool = tool

        // Comparing revisions is cheap. Comparing `dataRepresentation()` on
        // every SwiftUI update serialized the whole drawing twice per slider
        // tick, and a spurious byte mismatch wiped the undo history.
        if context.coordinator.appliedDrawingRevision != drawingRevision {
            context.coordinator.appliedDrawingRevision = drawingRevision
            context.coordinator.applyDrawing(drawing, to: canvasView)
            onDrawingApplied(drawingRevision)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}

extension PencilKitCanvasView {
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilKitCanvasView
        var appliedDrawingRevision = 0
        /// True while we push a drawing into the canvas ourselves, so the
        /// resulting delegate callback doesn't feed that programmatic change back
        /// into the view model (which would mutate observed state mid-update).
        private var isApplyingDrawingProgrammatically = false

        init(parent: PencilKitCanvasView) {
            self.parent = parent
        }

        /// Pushes a drawing into the canvas while suppressing the delegate
        /// callback the assignment triggers, so a programmatic update never loops
        /// back into the view model.
        func applyDrawing(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
            isApplyingDrawingProgrammatically = true
            defer { isApplyingDrawingProgrammatically = false }
            canvasView.drawing = drawing
        }

        /// Called for an eraser change and for a finished pen or pencil stroke,
        /// which the canvas adds to its drawing itself.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingDrawingProgrammatically else {
                return
            }
            parent.onDrawingChange(canvasView.drawing)
        }

        func canvasViewDidFinishRendering(_: PKCanvasView) {
            parent.onFinishRendering()
        }

        /// PencilKit's drawing gesture only erases. Pen and pencil strokes
        /// report through `PaeoniaDrawingCanvasView.onInkStrokeInProgressChange`.
        func canvasViewDidBeginUsingTool(_: PKCanvasView) {
            parent.onStrokeInProgressChange(true)
        }

        func canvasViewDidEndUsingTool(_: PKCanvasView) {
            parent.onStrokeInProgressChange(false)
        }
    }
}
