import PencilKit
import SwiftUI

/// Shows the partner's strokes while they draw them, on top of the canvas, and
/// on the Home tab also their whole canvas. It is a PencilKit canvas that takes
/// no touches, so the strokes have the real pen and pencil look.
struct WidgetLiveOverlayView: UIViewRepresentable {
    let live: WidgetLiveDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        canvasView.isUserInteractionEnabled = false
        context.coordinator.start(canvasView)
        return canvasView
    }

    func updateUIView(_: PKCanvasView, context _: Context) {}

    static func dismantleUIView(_: PKCanvasView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(live: live)
    }

    final class Coordinator: NSObject {
        private let live: WidgetLiveDrawing
        private weak var canvasView: PKCanvasView?
        private var displayLink: CADisplayLink?
        private var wasShowingLiveStrokes = false
        private var shownRoomVersion: Int?
        private var shownSide: CGFloat?

        init(live: WidgetLiveDrawing) {
            self.live = live
        }

        func start(_ canvasView: PKCanvasView) {
            self.canvasView = canvasView
            let displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ displayLink: CADisplayLink) {
            guard let canvasView else {
                return
            }
            let side = WidgetDrawingViewModel.canvasSide(for: canvasView.bounds.size)
            // Rebuild the drawing only while something moves or changed.
            guard live.hasLiveStrokes || wasShowingLiveStrokes
                || live.roomVersion != shownRoomVersion || side != shownSide
            else {
                return
            }
            canvasView.drawing = PKDrawing(strokes: live.overlayStrokes(at: CACurrentMediaTime(), side: side))
            wasShowingLiveStrokes = live.hasLiveStrokes
            shownRoomVersion = live.roomVersion
            shownSide = side
        }
    }
}
