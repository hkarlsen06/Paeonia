import PencilKit
import SwiftUI

/// What the guesser looks at inside the square: the live canvas, the replay, or a
/// spinner or a retry while the drawing loads. Pressing anywhere holds the
/// replay at 4x.
struct DrawAndGuessReplayCanvas: View {
    let viewModel: DrawAndGuessViewModel
    let side: CGFloat
    @AppStorage("games.drawAndGuess.holdHintShown") private var holdHintShown = false
    @State private var showsHoldHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content
            if viewModel.guessSource == .replay, viewModel.isReplayReady {
                overlays
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: holdChanged)
        .task(id: viewModel.isReplayReady) {
            guard viewModel.isReplayReady, !holdHintShown else { return }
            holdHintShown = true
            withAnimation(PaeoniaMotion.stateChange) { showsHoldHint = true }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(PaeoniaMotion.meaningfulMoment) { showsHoldHint = false }
        }
    }

    private func holdChanged(_ isPressing: Bool) {
        guard canFastForward, viewModel.isFastForwarding != isPressing else { return }
        if isPressing { PaeoniaHaptics.selection() }
        viewModel.setFastForward(isPressing)
    }

    private var canFastForward: Bool {
        viewModel.guessSource == .replay && viewModel.isReplayReady
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.guessSource == .live || viewModel.phase == .watchingLive, let live = viewModel.live {
            WidgetLiveOverlayView(live: live)
                .allowsHitTesting(false)
        } else if viewModel.isReplayReady {
            DrawAndGuessReplaySurface(frames: viewModel.replayFrames, side: side)
                .allowsHitTesting(false)
        } else if viewModel.phase != .reveal {
            // On the reveal, `DrawAndGuessRevealDrawing` shows the spinner or the error.
            DrawAndGuessDrawingPlaceholder(viewModel: viewModel)
        }
    }

    private var overlays: some View {
        ZStack {
            progressLine
            if viewModel.isFastForwarding {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .padding(PaeoniaSpacing.space12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
            }
            if showsHoldHint {
                Text(.gamesDrawAndGuessGuessHoldHint)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextPrimary)
                    .padding(.horizontal, PaeoniaSpacing.space12)
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
                    .padding(.bottom, PaeoniaSpacing.space16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    /// A thin line along the bottom edge that shows how much of the drawing has played.
    private var progressLine: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: viewModel.phase == .reveal)) { _ in
            let progress = viewModel.replayProgress(atWall: CACurrentMediaTime())
            Rectangle()
                .fill(.paeoniaAccentPrimary.opacity(0.6))
                .frame(width: side * progress, height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .opacity(progress >= 1 ? 0 : 1)
        }
    }
}

/// What a replay surface draws on each screen frame.
struct DrawAndGuessReplayFrames {
    /// The drawing at a wall time, scaled to `side`. Nil while there is nothing to play.
    let drawing: @MainActor (_ wall: TimeInterval, _ side: CGFloat) -> PKDrawing?
    let isFinished: @MainActor (_ wall: TimeInterval) -> Bool
}

/// Draws a replay on a canvas that takes no touches, on every screen frame while
/// the drawing is still moving. The guesser's own replay and the drawer's view of
/// it both use it.
struct DrawAndGuessReplaySurface: UIViewRepresentable {
    let frames: DrawAndGuessReplayFrames
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
        var frames: DrawAndGuessReplayFrames
        var side: CGFloat
        private weak var canvasView: PKCanvasView?
        private var displayLink: CADisplayLink?
        private var drawnSide: CGFloat = 0
        private var finishedDrawing = false

        init(frames: DrawAndGuessReplayFrames, side: CGFloat) {
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

        @objc private func step(_: CADisplayLink) {
            guard let canvasView else { return }
            let wall = CACurrentMediaTime()
            let isFinished = frames.isFinished(wall)
            // Once the last stroke is drawn there is nothing left to redraw.
            if isFinished, finishedDrawing, drawnSide == side { return }
            guard let drawing = frames.drawing(wall, side) else { return }
            canvasView.drawing = drawing
            finishedDrawing = isFinished
            drawnSide = side
        }
    }
}
