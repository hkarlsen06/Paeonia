import PencilKit
import SwiftUI

struct PencilKitCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    /// Changes only when the view model replaced the drawing from code. Strokes
    /// drawn on the canvas never change it, so they are not pushed back in.
    let drawingRevision: Int
    let tool: any PKTool
    let toolConfigurationRevision: Int
    let onCanvasReady: (PKCanvasView) -> Void
    let onDrawingChange: (PKDrawing, UndoManager?) -> Void
    let onStrokeInProgressChange: (Bool) -> Void
    /// The canvas now shows the drawing of this `drawingRevision`.
    var onDrawingApplied: (Int) -> Void = { _ in }
    /// The canvas finished rendering. The pixel eraser can change the drawing
    /// without `canvasViewDrawingDidChange`, so this is a moment to read it again.
    var onFinishRendering: () -> Void = {}

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        // Assign the initial drawing before wiring the delegate so this
        // programmatic assignment can't bounce back through
        // `canvasViewDrawingDidChange` while SwiftUI is still building the view.
        canvasView.drawing = drawing
        context.coordinator.appliedDrawingRevision = drawingRevision
        onDrawingApplied(drawingRevision)
        canvasView.delegate = context.coordinator
        context.coordinator.applyToolIfNeeded(
            tool,
            to: canvasView,
            revision: toolConfigurationRevision
        )
        context.coordinator.bind(canvasView)
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyToolIfNeeded(
            tool,
            to: canvasView,
            revision: toolConfigurationRevision
        )

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

extension PKCanvasView {
    func configureForPaeoniaDrawingCanvas() {
        backgroundColor = .clear
        drawingPolicy = .anyInput
        isOpaque = false
        isScrollEnabled = false
        overrideUserInterfaceStyle = .light
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
    }
}

extension PencilKitCanvasView {
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilKitCanvasView
        var appliedDrawingRevision = 0
        private var appliedToolConfigurationRevision: Int?
        /// True while we push a drawing into the canvas ourselves, so the
        /// resulting delegate callback doesn't feed that programmatic change back
        /// into the view model (which would mutate observed state mid-update).
        private var isApplyingDrawingProgrammatically = false

        init(parent: PencilKitCanvasView) {
            self.parent = parent
        }

        func applyToolIfNeeded(
            _ tool: any PKTool,
            to canvasView: PKCanvasView,
            revision: Int
        ) {
            guard appliedToolConfigurationRevision != revision else {
                return
            }

            canvasView.tool = tool
            appliedToolConfigurationRevision = revision
        }

        func bind(_ canvasView: PKCanvasView) {
            parent.onCanvasReady(canvasView)
        }

        /// Pushes a drawing into the canvas while suppressing the delegate
        /// callback the assignment triggers, so a programmatic update never loops
        /// back into the view model.
        func applyDrawing(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
            isApplyingDrawingProgrammatically = true
            defer { isApplyingDrawingProgrammatically = false }
            canvasView.drawing = drawing
            // Make the loaded drawing the clean undo baseline. Otherwise PencilKit
            // keeps the snapshot from before this programmatic load, so undoing the
            // user's first stroke reverts to that stale (often empty) snapshot and
            // wipes the loaded drawing instead of just removing the stroke.
            canvasView.undoManager?.removeAllActions()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingDrawingProgrammatically else {
                return
            }
            parent.drawing = canvasView.drawing
            parent.onDrawingChange(canvasView.drawing, canvasView.undoManager)
        }

        func canvasViewDidFinishRendering(_: PKCanvasView) {
            parent.onFinishRendering()
        }

        func canvasViewDidBeginUsingTool(_: PKCanvasView) {
            parent.onStrokeInProgressChange(true)
        }

        func canvasViewDidEndUsingTool(_: PKCanvasView) {
            parent.onStrokeInProgressChange(false)
        }
    }
}
