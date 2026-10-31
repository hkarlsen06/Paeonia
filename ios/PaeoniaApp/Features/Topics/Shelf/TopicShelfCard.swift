import SwiftUI

/// One topic on the shelf: a tactile card with the topic's picture, its tint over the
/// plum, its name, and how far the couple has come. Glows while the partner has
/// answered questions waiting for this person.
struct TopicShelfCard: View {
    let topic: TopicSummary
    let newCount: Int

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)

    private var tint: Color {
        TopicStyle.tint(for: topic.id)
    }

    private var isWaitingForYou: Bool {
        topic.forYouCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            TopicArtwork(topicKey: topic.id, height: 88)
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .padding(.bottom, PaeoniaSpacing.space8)

            Text(topic.title)
                .font(PaeoniaTypography.collectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(topic.subtitle)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: PaeoniaSpacing.space8)

            TopicProgressLine(topic: topic)
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .paeoniaCardSurface(
            in: shape,
            fill: LinearGradient(
                stops: [
                    .init(color: tint.opacity(0.42), location: 0),
                    .init(color: .paeoniaSurfacePrimary, location: 0.62),
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            needsAttention: isWaitingForYou
        )
        .overlay(alignment: .topTrailing) {
            badge
                .padding(PaeoniaSpacing.space8)
        }
        .contentShape(shape)
    }

    @ViewBuilder
    private var badge: some View {
        if isWaitingForYou {
            TopicBadge(text: .topicsBadgeForYou(topic.forYouCount))
        } else if newCount > 0 {
            TopicBadge(text: .topicsBadgeNew(newCount))
        }
    }
}
