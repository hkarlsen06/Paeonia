import SwiftUI

/// The partner's avatar next to one line of status, such as "Robin is reading
/// along". Presence and writing use separate cues.
struct StoryChainPartnerLine: View {
    let participants: GameParticipants
    let text: LocalizedStringResource
    let isHere: Bool
    var showsDots = false
    var font = PaeoniaTypography.caption.weight(.semibold)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let avatarSize: CGFloat = 24

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            StoryChainAvatar(participants: participants, isMe: false, size: Self.avatarSize)
                .accessibilityHidden(true)
                .gamePresenceRing(isHere)
                .padding(.vertical, 3)
            Text(text)
                .font(font)
                .foregroundStyle(isHere ? .paeoniaTextPrimary : .paeoniaTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if showsDots, !dynamicTypeSize.isAccessibilitySize {
                GameTypingDots()
            }
        }
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.space24, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isHere ? .gamesPresenceHere : .gamesPresenceAway))
    }
}
