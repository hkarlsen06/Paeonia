import SwiftUI

/// Shown once per phone when the couple has answered every question they kept in a
/// topic. A moment over the topic, not a badge: the answers stay there to read.
struct TopicFinishedView: View {
    let topic: TopicSummary
    let onDone: () -> Void

    @Environment(\.petalShower) private var petalShower

    var body: some View {
        ZStack {
            Color.paeoniaBackgroundSecondary.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: PaeoniaSpacing.space16) {
                TopicArtwork(topicKey: topic.id, height: 120)

                Text(.topicsFinishedTitle(topic.title))
                    .font(PaeoniaTypography.collectionHeroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(.topicsFinishedMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onDone) {
                    Text(.topicsFinishedButton)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .padding(.top, PaeoniaSpacing.space8)
            }
            .padding(.horizontal, PaeoniaSpacing.space32)
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        }
        // Waits for the view to fade in over the topic.
        .onAppear { petalShower(seed: "topic.\(topic.id)", after: 0.25) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
