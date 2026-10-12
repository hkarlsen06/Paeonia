import SwiftUI

/// "Speed bonus +1" in the live row. Gold marks only this. It fades out when the
/// 30 seconds are over, with no sound, no haptic and nothing turning red.
struct DrawAndGuessSpeedBonusLabel: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let isAvailable = viewModel.speedBonusIsAvailable
            Label {
                Text(.gamesDrawAndGuessGuessSpeedBonus)
            } icon: {
                Image(systemName: "bolt.fill")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(Color.paeoniaInkGold)
            .opacity(isAvailable ? 1 : 0)
            .animation(PaeoniaMotion.meaningfulMoment, value: isAvailable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.gamesDrawAndGuessGuessSpeedBonusA11Y))
            .accessibilityHidden(!isAvailable)
        }
    }
}

/// A 3 point gold line under the replay that drains from full to empty over the
/// 30 seconds. Reduce Motion drops it and keeps the label alone.
struct DrawAndGuessSpeedBonusLine: View {
    let viewModel: DrawAndGuessViewModel
    let width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isCounting)) { _ in
            let isAvailable = viewModel.speedBonusIsAvailable
            let fraction = (viewModel.speedBonusRemaining() ?? DrawAndGuessSpeedBonus.window)
                / DrawAndGuessSpeedBonus.window
            Capsule()
                .fill(Color.paeoniaInkGold)
                .frame(width: width * fraction, height: 3)
                .frame(width: width, alignment: .leading)
                .opacity(isAvailable ? 1 : 0)
                .animation(PaeoniaMotion.meaningfulMoment, value: isAvailable)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var isCounting: Bool {
        if case .counting = viewModel.speedBonus { true } else { false }
    }
}
