import PencilKit
import SwiftUI

/// Draws a replay on a canvas that takes no touches, on every screen frame while
/// the drawing is still moving. The guesser's own replay and the drawer's view of
/// it both use it.
struct GameReplaySurface: UIViewRepresentable {
    let frames: GameReplayFrames
    let side: CGFloat

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        canvasView.isUserInteractionEnabled = false
        context.coordinator.start(canvasView)
        return canvasView
    }

    func updateUIView(_: PKCanvasView, context: Context) {
        context.coordinator.side = side
        context.coordinator.frames = frames
    }

    static func dismantleUIView(_: PKCanvasView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(frames: frames, side: side)
    }

    @MainActor
    final class Coordinator: NSObject {
        // New frames or a new size may need drawing again, so the link wakes up.
        var frames: GameReplayFrames { didSet { displayLink?.isPaused = false } }
        var side: CGFloat { didSet { displayLink?.isPaused = false } }
        private weak var canvasView: PKCanvasView?
        private var displayLink: CADisplayLink?
        private var drawnSide: CGFloat = 0
        private var finishedDrawing = false

        init(frames: GameReplayFrames, side: CGFloat) {
            self.frames = frames
            self.side = side
        }

        func start(_ canvasView: PKCanvasView) {
            self.canvasView = canvasView
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard let canvasView else { return }
            let wall = CACurrentMediaTime()
            let isFinished = frames.isFinished(wall)
            // Once the last stroke is drawn there is nothing left to redraw, so the link sleeps.
            if isFinished, finishedDrawing, drawnSide == side {
                link.isPaused = true
                return
            }
            guard let drawing = frames.drawing(wall, side) else { return }
            canvasView.drawing = drawing
            finishedDrawing = isFinished
            drawnSide = side
        }
    }
}
