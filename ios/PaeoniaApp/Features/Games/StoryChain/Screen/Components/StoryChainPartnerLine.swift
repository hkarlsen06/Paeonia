import SwiftUI

/// The partner's avatar next to one line of status, such as "Robin is reading
/// along". The ring breathes around the avatar while the partner is live, and
/// three dots breathe after the text while they write.
struct StoryChainPartnerLine: View {
    let participants: GameParticipants
    let text: LocalizedStringResource
    var showsRing = false
    var showsDots = false
    var font = PaeoniaTypography.caption.weight(.semibold)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let avatarSize: CGFloat = 24

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            StoryChainAvatar(participants: participants, isMe: false, size: Self.avatarSize)
                .accessibilityHidden(true)
                .background {
                    StoryChainBreathingRing(
                        isActive: showsRing,
                        lineWidth: 2,
                        inset: 3,
                        blur: 0.5,
                        peak: 1,
                        trough: 0.4
                    )
                }
                .padding(.vertical, 3)
                .padding(.leading, 3)
            Text(text)
                .font(font)
                .foregroundStyle(showsRing || showsDots ? .paeoniaTextPrimary : .paeoniaTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if showsDots, !dynamicTypeSize.isAccessibilitySize {
                StoryChainTypingDots(ink: StoryChainPageStyle.partnerInk)
            }
        }
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.space24, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
