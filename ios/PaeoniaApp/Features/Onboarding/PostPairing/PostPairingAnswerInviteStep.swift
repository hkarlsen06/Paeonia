import SwiftUI

/// The partner already answered the couple's first question, which waits for this
/// person. The answer stays hidden until this person answers too, which is the pull to
/// answer now.
struct PostPairingAnswerInviteStep: View {
    let partnerName: String
    let onFinish: (_ answerNow: Bool) -> Void

    @State private var isShown = false
    @State private var hasFinished = false
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 52

    var body: some View {
        OnboardingStepScaffold(
            title: .onboardingFirstDayAnswersTitle(partnerName),
            message: .onboardingFirstDayAnswersMessage(partnerName),
            placement: .standalone,
            primary: OnboardingStepAction(title: .onboardingFirstDayAnswersNowButton) {
                finish(answerNow: true)
            },
            secondary: OnboardingStepAction(title: .onboardingFirstDayLaterButton) {
                finish(answerNow: false)
            }
        ) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.paeoniaAccentSecondary, .paeoniaAccentPrimary)
                .symbolEffect(.bounce, value: isShown)
                .accessibilityHidden(true)
        } content: {
            EmptyView()
        }
        .task {
            // A beat after the entrance, so the bounce is seen.
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else {
                return
            }
            isShown = true
            // Something from the partner is waiting.
            GameSound.nudge.play(volume: 0.6)
        }
    }

    private func finish(answerNow: Bool) {
        guard !hasFinished else {
            return
        }
        hasFinished = true
        if answerNow {
            PaeoniaHaptics.celebrationContinued()
        }
        onFinish(answerNow)
    }
}

#if DEBUG
#Preview {
    PostPairingAnswerInviteStep(partnerName: "Hjalmar", onFinish: { _ in })
        .preferredColorScheme(.dark)
}
#endif
