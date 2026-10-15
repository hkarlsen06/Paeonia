import PencilKit
import SwiftUI

struct PencilKitCanvasView: UIViewRepresentable {
    let drawing: PKDrawing
    /// Changes only when the view model replaced the drawing from code. Strokes
    /// drawn on the canvas never change it, so they are not pushed back in.
    let drawingRevision: Int
    let tool: any PKTool
    let toolConfigurationRevision: Int
    let onCanvasReady: (PKCanvasView) -> Void
    let onDrawingChange: (PKDrawing) -> Void
    let onStrokeInProgressChange: (Bool) -> Void
    /// The paint bucket is picked: a tap fills instead of drawing.
    var isFillToolSelected = false
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

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PaeoniaDrawingCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        canvasView.overscanTop = overscanTop
        let fillTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.fillTapped))
        canvasView.addGestureRecognizer(fillTap)
        context.coordinator.fillTap = fillTap
        context.coordinator.applyFillMode(isFillToolSelected, to: canvasView)
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
        (canvasView as? PaeoniaDrawingCanvasView)?.overscanTop = overscanTop
        context.coordinator.applyToolIfNeeded(
            tool,
            to: canvasView,
            revision: toolConfigurationRevision
        )
        context.coordinator.applyFillMode(isFillToolSelected, to: canvasView)

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

/// A canvas without PencilKit's undo stack. The view models keep their own
/// (`DrawingEditHistory`), and PencilKit's would undo to drawings that are gone.
final class PaeoniaDrawingCanvasView: PKCanvasView {
    override var undoManager: UndoManager? { nil }

    /// See `PencilKitCanvasView.overscanTop`. The canvas is scrolled up by this
    /// much, so the drawing's y 0 sits this far below the view's top edge.
    var overscanTop: CGFloat = 0 {
        didSet {
            guard overscanTop != oldValue else { return }
            contentInsetAdjustmentBehavior = .never
            contentInset.top = overscanTop
            contentOffset = CGPoint(x: 0, y: -overscanTop)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A layout pass may move the offset back to the content's top.
        let pinned = CGPoint(x: 0, y: -overscanTop)
        if overscanTop > 0, contentOffset != pinned {
            contentOffset = pinned
        }
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
        weak var fillTap: UITapGestureRecognizer?
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

        /// Turns off the drawing gesture, not `isDrawingEnabled`. With
        /// `isDrawingEnabled` off, the canvas did not redraw the filled drawing
        /// until much later.
        func applyFillMode(_ isFillToolSelected: Bool, to canvasView: PKCanvasView) {
            canvasView.drawingGestureRecognizer.isEnabled = !isFillToolSelected
            fillTap?.isEnabled = isFillToolSelected
        }

        @objc func fillTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else {
                return
            }
            parent.onFill(recognizer.location(in: view))
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
            parent.onDrawingChange(canvasView.drawing)
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
