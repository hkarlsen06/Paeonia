import SwiftUI

/// Text and shape identify story state even when a portrait has colorful decorations.
struct StoryStatusBadge: View {
    let ring: StoryRingState

    var body: some View {
        if ring != .noStory {
            Label {
                Text(ring == .unseen ? .storiesHomeNewStory : .storiesHomeViewStory)
            } icon: {
                Image(systemName: ring == .unseen ? "play.fill" : "eye")
            }
            .modifier(StoryBadgeStyle(isHighlighted: ring == .unseen))
            .accessibilityHidden(true)
        }
    }
}

/// Shared capsule treatment for story status and the add action below decorated portraits.
struct StoryBadgeStyle: ViewModifier {
    var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .labelStyle(StoryActionLabelStyle())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, PaeoniaSpacing.space8)
            .padding(.vertical, PaeoniaSpacing.space4)
            .foregroundStyle(isHighlighted ? .paeoniaTextInverse : .paeoniaTextPrimary)
            .background(isHighlighted ? Color.paeoniaAccentPrimary : .paeoniaBackgroundSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(.paeoniaTextPrimary.opacity(0.7), lineWidth: 1))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StoryActionLabelStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space4))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space4))
        layout {
            configuration.icon
            configuration.title
        }
    }
}
