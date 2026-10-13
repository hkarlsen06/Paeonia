import SwiftUI

/// The square on the drawer's result screen. While the partner replays the
/// drawing, it plays where their replay is. Otherwise it shows the whole drawing.
struct DrawAndGuessDrawerSquareContent: View {
    let viewModel: DrawAndGuessViewModel
    let partnerGuess: DrawAndGuessPartnerGuess?
    let side: CGFloat

    private var followsReplay: Bool { partnerGuess?.replayClock != nil }

    var body: some View {
        ZStack {
            if followsReplay {
                DrawAndGuessReplaySurface(frames: viewModel.partnerReplayFrames, side: side)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else {
                DrawAndGuessRevealDrawing(viewModel: viewModel, side: side)
                    .transition(.opacity)
            }
        }
        // Only opacity changes, so this also suits Reduce Motion.
        .animation(PaeoniaMotion.stateChange, value: followsReplay)
    }
}

/// The letters the partner has placed, as their answer slots show them, while
/// they guess on their screen.
struct DrawAndGuessPartnerSlots: View {
    let guess: DrawAndGuessPartnerGuess
    let partnerName: String

    /// Never begins, so the slots never light up as on the reveal.
    @State private var timeline = DrawAndGuessRevealTimeline()
    @Namespace private var namespace

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.gamesDrawAndGuessResultGuessing(partnerName))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            DrawAndGuessAnswerSlots(
                slots: guess.slots,
                timeline: timeline,
                namespace: namespace,
                isRevealed: false,
                litsGreen: false,
                wrongGuessCount: guess.wrongCount,
                isShowingWrongGuess: guess.isWrong
            )
        }
        .accessibilityIdentifier("draw.result.partnerSlots")
    }
}
