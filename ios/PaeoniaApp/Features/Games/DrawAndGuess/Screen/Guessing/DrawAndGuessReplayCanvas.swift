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
            GameReplaySurface(frames: viewModel.replayFrames, side: side)
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
        DrawAndGuessReplayProgressLine(viewModel: viewModel, side: side)
    }
}

/// Follows the replay about 30 times a second until it ends, then stops.
private struct DrawAndGuessReplayProgressLine: View {
    let viewModel: DrawAndGuessViewModel
    let side: CGFloat
    @State private var progress = 0.0

    var body: some View {
        Rectangle()
            .fill(.paeoniaAccentPrimary.opacity(0.6))
            .frame(width: side * progress, height: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .opacity(progress >= 1 ? 0 : 1)
            .task(id: viewModel.phase) {
                while !Task.isCancelled {
                    progress = viewModel.replayProgress(atWall: CACurrentMediaTime())
                    guard progress < 1, viewModel.phase != .reveal else { return }
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
    }
}
