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
                GameReplaySurface(frames: viewModel.partnerReplayFrames, side: side)
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

/// The tiles under the drawer's square while the round is open. They spell the
/// word, and while the partner guesses on their screen they show the partner's
/// letters in the same place, so nothing moves when the partner starts.
struct DrawAndGuessDrawerSlots: View {
    let word: String
    let guess: DrawAndGuessPartnerGuess?
    let partnerName: String

    /// Never begins, so the slots never light up as on the reveal.
    @State private var timeline = DrawAndGuessRevealTimeline()
    @Namespace private var namespace

    private var wordSlots: DrawAndGuessSlots {
        let answer = DrawAndGuessSlots(answer: word).answer
        return DrawAndGuessSlots(answer: word, letters: answer.map(Optional.some))
    }

    private var label: LocalizedStringResource {
        guess == nil ? .gamesDrawAndGuessResultYourWord : .gamesDrawAndGuessResultGuessing(partnerName)
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(label)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            DrawAndGuessAnswerSlots(
                slots: guess?.slots ?? wordSlots,
                timeline: timeline,
                namespace: namespace,
                isRevealed: false,
                litsGreen: false,
                wrongGuessCount: guess?.wrongCount ?? 0,
                isShowingWrongGuess: guess?.isWrong ?? false
            )
            // A new view when the partner starts or stops, so their shake count
            // going back to 0 does not shake the word.
            .id(guess == nil)
            .transition(.opacity)
        }
        .accessibilityIdentifier("draw.result.partnerSlots")
    }
}
