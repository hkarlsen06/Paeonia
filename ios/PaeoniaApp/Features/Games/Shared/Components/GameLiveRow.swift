import SwiftUI

/// Centers related activity items, sharing a row only when their full text fits.
/// Larger text stacks the items and lets each status wrap at its natural size.
struct GameLiveRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PaeoniaSpacing.space12) {
                        leading
                        trailing
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    stacked
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.space24)
        .padding(.horizontal, PaeoniaSpacing.space8)
    }

    private var stacked: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            leading
            trailing
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An existing portrait and status, with presence independent of progress.
struct GamePresenceLabel: View {
    let player: GamePlayer
    let text: LocalizedStringResource
    let isHere: Bool

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            GameAvatar(player: player, isMe: false, size: 24)
                .gamePresenceRing(isHere)
                .accessibilityHidden(true)
            Text(text)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(isHere ? .paeoniaTextPrimary : .paeoniaTextTertiary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isHere ? .gamesPresenceHere : .gamesPresenceAway))
    }
}
