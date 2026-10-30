import SwiftUI

/// Text and shape identify story state even when a portrait has colorful decorations.
struct StoryStatusBadge: View {
    let ring: StoryRingState
    var isOwn = false

    var body: some View {
        if ring != .noStory {
            Label {
                Text(isOwn ? .storiesBadgeOwn : ring == .unseen ? .storiesBadgeNew : .storiesBadgeSeen)
            } icon: {
                Image(systemName: isOwn || ring == .unseen ? "play.fill" : "checkmark")
            }
            .font(.caption2.weight(.bold))
            .padding(.horizontal, PaeoniaSpacing.space8)
            .padding(.vertical, PaeoniaSpacing.space4)
            .foregroundStyle(ring == .unseen && !isOwn ? .paeoniaTextInverse : .paeoniaTextPrimary)
            .background(ring == .unseen && !isOwn ? Color.paeoniaAccentPrimary : .paeoniaBackgroundSecondary,
                        in: Capsule())
            .overlay(Capsule().strokeBorder(.paeoniaTextPrimary.opacity(0.7), lineWidth: 1))
            // A compact map marker. VoiceOver reads the full story state on its button.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .fixedSize()
            .accessibilityHidden(true)
        }
    }
}
