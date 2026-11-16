import SwiftUI

/// How long the guess took, in a small capsule under the reveal's headline: a
/// stopwatch and "18 sec". It runs up from zero when it appears and slows to a
/// stop on the time. The stopwatch turns gold when the guess earned the speed
/// bonus, because gold marks speed in this game.
struct DrawAndGuessSolveTime: View {
    let ms: Int
    let earnedSpeedBonus: Bool
    /// False on a skipped reveal and with Reduce Motion, where the time shows at once.
    let animates: Bool

    @State private var shownMs: Int

    /// How long the count from zero takes.
    private static let countDuration: Double = 0.8
    private static let countSteps = 16

    init(ms: Int, earnedSpeedBonus: Bool, animates: Bool) {
        self.ms = ms
        self.earnedSpeedBonus = earnedSpeedBonus
        self.animates = animates
        _shownMs = State(initialValue: animates ? 0 : ms)
    }

    var body: some View {
        Label {
            Text(DrawAndGuessHistoryFormat.duration(ms: shownMs))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(shownMs)))
        } icon: {
            Image(systemName: "stopwatch.fill")
                .foregroundStyle(earnedSpeedBonus ? Color.paeoniaInkGold : .paeoniaTextSecondary)
        }
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.gamesDrawAndGuessRevealTimeA11Y(
            DrawAndGuessHistoryFormat.duration(ms: ms, width: .wide)
        )))
        .accessibilityIdentifier("draw.reveal.time")
        .task { await countUp() }
        // A tap that skips the reveal, or the server's time replacing the phone's, settles it.
        .onChange(of: animates) { _, animates in
            if !animates { shownMs = ms }
        }
        .onChange(of: ms) { _, newMs in shownMs = newMs }
    }

    /// Steps from zero to the time on an ease-out curve, so it slows as it stops.
    private func countUp() async {
        guard animates, shownMs < ms else { return }
        for step in 1...Self.countSteps {
            try? await Task.sleep(for: .seconds(Self.countDuration / Double(Self.countSteps)))
            guard !Task.isCancelled, animates else { return }
            let progress = Double(step) / Double(Self.countSteps)
            let eased = 1 - pow(1 - progress, 3)
            withAnimation(PaeoniaMotion.buttonPress) {
                shownMs = Int((Double(ms) * eased).rounded())
            }
        }
    }
}
