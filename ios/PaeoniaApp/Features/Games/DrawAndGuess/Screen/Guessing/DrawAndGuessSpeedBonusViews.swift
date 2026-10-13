import SwiftUI

/// "Speed bonus +2" for the first 15 seconds, then "Speed bonus +1" until 30
/// seconds. Gold marks only this. It fades out when the time is over, with no
/// sound, no haptic and nothing turning red.
struct DrawAndGuessSpeedBonusLabel: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let tier = viewModel.speedBonusTier
            // The label keeps the last tier while it fades, so it never flashes "+0".
            Label {
                Text(.gamesDrawAndGuessGuessSpeedBonus(max(tier, 1)))
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "bolt.fill")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(Color.paeoniaInkGold)
            .opacity(tier > 0 ? 1 : 0)
            .animation(PaeoniaMotion.meaningfulMoment, value: tier)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spokenHint(tier: tier)))
            .accessibilityHidden(tier == 0)
        }
    }

    private func spokenHint(tier: Int) -> LocalizedStringResource {
        tier >= DrawAndGuessSpeedBonus.fastPoints
            ? .gamesDrawAndGuessGuessSpeedBonusFastA11Y
            : .gamesDrawAndGuessGuessSpeedBonusA11Y
    }
}

/// A 3 point gold line under the replay that drains from full to empty over the
/// 30 seconds. A small notch marks the 15 second point, where the bonus drops
/// from 2 to 1. Reduce Motion drops the line and keeps the label alone.
struct DrawAndGuessSpeedBonusLine: View {
    let viewModel: DrawAndGuessViewModel
    let width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isCounting)) { _ in
            let isAvailable = viewModel.speedBonusIsAvailable
            let remaining = viewModel.speedBonusRemaining() ?? DrawAndGuessSpeedBonus.window
            let fraction = remaining / DrawAndGuessSpeedBonus.window
            let notch = DrawAndGuessSpeedBonus.fastWindow / DrawAndGuessSpeedBonus.window
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.paeoniaInkGold)
                    .frame(width: width * fraction, height: 3)
                // The line reaches the notch when the bonus drops, and the notch goes with it.
                Capsule()
                    .fill(Color.paeoniaInkGold)
                    .frame(width: 2, height: 9)
                    .offset(x: width * notch - 1)
                    .opacity(fraction > notch ? 1 : 0)
            }
            .frame(width: width, alignment: .leading)
            .opacity(isAvailable ? 1 : 0)
            .animation(PaeoniaMotion.meaningfulMoment, value: isAvailable)
            .animation(PaeoniaMotion.stateChange, value: fraction > notch)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var isCounting: Bool {
        if case .counting = viewModel.speedBonus { true } else { false }
    }
}
