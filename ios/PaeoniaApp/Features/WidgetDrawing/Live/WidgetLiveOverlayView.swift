import PencilKit
import SwiftUI

/// Shows the partner's strokes while they draw them, on top of the canvas, and
/// on the Home tab also their whole canvas. It is two PencilKit canvases that
/// take no touches, so the strokes have the real pen and pencil look. The lower
/// one holds the partner's whole canvas and changes only when that does. The
/// upper one holds the strokes in progress, which change on every frame.
struct WidgetLiveOverlayView: UIViewRepresentable {
    let live: WidgetLiveDrawing

    func makeUIView(context: Context) -> LayeredCanvasView {
        let container = LayeredCanvasView()
        context.coordinator.start(container)
        return container
    }

    func updateUIView(_: LayeredCanvasView, context _: Context) {}

    static func dismantleUIView(_: LayeredCanvasView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(live: live)
    }

    final class Coordinator: NSObject {
        private let live: WidgetLiveDrawing
        private weak var container: LayeredCanvasView?
        private var displayLink: CADisplayLink?
        private var observationTask: Task<Void, Never>?
        private var wasShowingLiveStrokes = false
        private var shownRoomVersion: Int?
        private var shownSide: CGFloat?

        init(live: WidgetLiveDrawing) {
            self.live = live
        }

        func start(_ container: LayeredCanvasView) {
            self.container = container
            container.onLayout = { [weak self] in
                self?.wake()
            }
            let displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink.capDrawingFrameRate()
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
            // The link sleeps once nothing moves, and wakes when the live
            // drawing changes.
            observationTask = Task { [weak self, live] in
                for await _ in Observations({ live.overlayRevision }) {
                    self?.wake()
                }
            }
        }

        func stop() {
            observationTask?.cancel()
            observationTask = nil
            displayLink?.invalidate()
            displayLink = nil
        }

        private func wake() {
            displayLink?.isPaused = false
        }

        @objc private func step(_ displayLink: CADisplayLink) {
            guard let container else {
                return
            }
            let side = WidgetDrawingViewModel.canvasSide(for: container.bounds.size)
            if live.roomVersion != shownRoomVersion || side != shownSide {
                container.lowerCanvas.drawing = PKDrawing(strokes: live.roomStrokes(side: side))
                shownRoomVersion = live.roomVersion
                shownSide = side
            }
            let liveStrokes = live.liveStrokes(at: CACurrentMediaTime(), side: side)
            if !liveStrokes.isEmpty || wasShowingLiveStrokes {
                container.upperCanvas.drawing = PKDrawing(strokes: liveStrokes)
            }
            wasShowingLiveStrokes = !liveStrokes.isEmpty
            if !live.hasLiveStrokes {
                displayLink.isPaused = true
            }
        }
    }
}
