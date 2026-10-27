import SwiftUI

/// The one line above the square: who is here on the left, a status on the right.
/// It is always laid out, so the square never moves when the status changes. At
/// accessibility text sizes the right side moves under the left.
struct GameLiveRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    leading
                    trailing
                }
            } else {
                HStack(spacing: PaeoniaSpacing.space8) {
                    leading
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                    Spacer(minLength: PaeoniaSpacing.space8)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.space24, alignment: .leading)
        .padding(.horizontal, PaeoniaSpacing.space8)
    }
}

/// An avatar next to a short status line. The green dot says the partner has the
/// game open, and the ring that they are watching this screen.
struct GamePresenceLabel: View {
    let player: GamePlayer
    let text: LocalizedStringResource
    var isHere = false
    var showsRing = false
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            GameAvatar(player: player, isMe: false, size: 24)
                .overlay {
                    if showsRing {
                        Circle().strokeBorder(.paeoniaAccentPrimary, lineWidth: 2).padding(-2)
                    }
                }
                .gamePresenceDot(isHere, size: 10)
                .scaleEffect(scale)
            Text(text)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(showsRing ? .paeoniaTextPrimary : .paeoniaTextTertiary)
        }
    }
}
