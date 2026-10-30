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
            .modifier(StoryBadgeStyle(isHighlighted: ring == .unseen && !isOwn))
            .accessibilityHidden(true)
        }
    }
}

/// Shared capsule treatment for story status and the add action below decorated portraits.
struct StoryBadgeStyle: ViewModifier {
    var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.bold))
            .padding(.horizontal, PaeoniaSpacing.space8)
            .padding(.vertical, PaeoniaSpacing.space4)
            .foregroundStyle(isHighlighted ? .paeoniaTextInverse : .paeoniaTextPrimary)
            .background(isHighlighted ? Color.paeoniaAccentPrimary : .paeoniaBackgroundSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(.paeoniaTextPrimary.opacity(0.7), lineWidth: 1))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .fixedSize()
    }
}
