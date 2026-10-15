import PencilKit
import SwiftUI

/// Draws a replay on a canvas that takes no touches, on every screen frame while
/// the drawing is still moving. The guesser's own replay and the drawer's view of
/// it both use it. Finished strokes sit on a lower canvas that is set again only
/// when another stroke finishes, and the stroke in progress sits above it.
struct GameReplaySurface: UIViewRepresentable {
    let frames: GameReplayFrames
    let side: CGFloat

    func makeUIView(context: Context) -> LayeredCanvasView {
        let container = LayeredCanvasView()
        context.coordinator.start(container)
        return container
    }

    func updateUIView(_: LayeredCanvasView, context: Context) {
        context.coordinator.side = side
        context.coordinator.frames = frames
    }

    static func dismantleUIView(_: LayeredCanvasView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(frames: frames, side: side)
    }

    private struct FittedTimeline {
        let id: UUID
        let side: CGFloat
        let timeline: GameReplayTimeline
    }

    @MainActor
    final class Coordinator: NSObject {
        // New frames or a new size may need drawing again, so the link wakes up.
        var frames: GameReplayFrames { didSet { wake() } }
        var side: CGFloat { didSet { wake() } }
        private weak var container: LayeredCanvasView?
        private var displayLink: CADisplayLink?
        private var fitted: FittedTimeline?
        private var shownFinishedCount: Int?
        /// `[index, point count]` for each stroke on the upper canvas. [-1] means unknown.
        private var shownPartialKey: [Int] = [-1]
        private var finishedDrawing = false

        init(frames: GameReplayFrames, side: CGFloat) {
            self.frames = frames
            self.side = side
        }

        func start(_ container: LayeredCanvasView) {
            self.container = container
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.capDrawingFrameRate()
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func wake() {
            finishedDrawing = false
            displayLink?.isPaused = false
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard let container else { return }
            let wall = CACurrentMediaTime()
            let isFinished = frames.isFinished(wall)
            // Once the last stroke is drawn there is nothing left to redraw, so the link sleeps.
            if isFinished, finishedDrawing, fitted?.side == side {
                link.isPaused = true
                return
            }
            guard let playback = frames.playback(wall) else { return }
            let timeline = fittedTimeline(playback.timeline)
            let progress = timeline.progress(at: playback.time)
            if progress.finishedCount != shownFinishedCount {
                container.lowerCanvas.drawing = PKDrawing(strokes: timeline.finishedStrokes(at: playback.time))
                shownFinishedCount = progress.finishedCount
            }
            let partialKey = progress.partials.flatMap { [$0.index, $0.stroke.path.count] }
            if partialKey != shownPartialKey {
                container.upperCanvas.drawing = PKDrawing(strokes: progress.partials.map(\.stroke))
                shownPartialKey = partialKey
            }
            finishedDrawing = isFinished
        }

        /// The timeline for the current size. Scaling every stroke on each frame
        /// is what this avoids, and the lower canvas starts over when it changes.
        private func fittedTimeline(_ timeline: GameReplayTimeline) -> GameReplayTimeline {
            if let fitted, fitted.id == timeline.id, fitted.side == side {
                return fitted.timeline
            }
            let scaled = timeline.fitted(toSide: side)
            fitted = FittedTimeline(id: timeline.id, side: side, timeline: scaled)
            shownFinishedCount = nil
            shownPartialKey = [-1]
            return scaled
        }
    }
}
