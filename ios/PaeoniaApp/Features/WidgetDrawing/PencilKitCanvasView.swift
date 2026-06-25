import PencilKit
import SwiftUI

struct PencilKitCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let tool: any PKTool
    let toolConfigurationRevision: Int
    let onCanvasReady: (PKCanvasView) -> Void
    let onDrawingChange: (PKDrawing, UndoManager?) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        // Assign the initial drawing before wiring the delegate so this
        // programmatic assignment can't bounce back through
        // `canvasViewDrawingDidChange` while SwiftUI is still building the view.
        canvasView.drawing = drawing
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

        if canvasView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            context.coordinator.applyDrawing(drawing, to: canvasView)
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
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingDrawingProgrammatically else {
                return
            }
            parent.drawing = canvasView.drawing
            parent.onDrawingChange(canvasView.drawing, canvasView.undoManager)
        }
    }
}
