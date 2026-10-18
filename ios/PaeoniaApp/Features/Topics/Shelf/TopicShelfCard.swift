import SwiftUI

/// One topic on the shelf: a tactile card with the topic's picture, its tint over the
/// plum, its name, and how far the couple has come. Glows while the partner has
/// answered questions waiting for this person.
struct TopicShelfCard: View {
    let topic: TopicSummary
    let partnerName: String
    let newCount: Int

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)

    private var tint: Color {
        TopicStyle.tint(for: topic.id)
    }

    private var isWaitingForYou: Bool {
        topic.isOpen && topic.forYouCount > 0
    }

    /// A pink glow while something waits for this person, a soft shadow otherwise.
    private var shadowColor: Color {
        isWaitingForYou ? Color.paeoniaAccentPrimary.opacity(0.3) : Color.black.opacity(0.22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            TopicArtwork(topicKey: topic.id, height: 88, isFrosted: !topic.isOpen)
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

            TopicProgressLine(topic: topic, partnerName: partnerName)
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background {
            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: tint.opacity(0.42), location: 0),
                            .init(color: .paeoniaSurfacePrimary, location: 0.62),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: shadowColor, radius: 14, y: 6)
        }
        .overlay {
            shape.strokeBorder(
                isWaitingForYou ? Color.paeoniaAccentPrimary.opacity(0.6) : Color.paeoniaTextPrimary.opacity(0.1),
                lineWidth: isWaitingForYou ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
        .overlay(alignment: .topTrailing) {
            badge
                .padding(PaeoniaSpacing.space8)
        }
        .contentShape(shape)
    }

    @ViewBuilder
    private var badge: some View {
        if topic.adultsOnly {
            TopicBadge(text: .topicsBadgeAdults, isProminent: false)
        } else if isWaitingForYou {
            TopicBadge(text: .topicsBadgeForYou(topic.forYouCount))
        } else if newCount > 0 {
            TopicBadge(text: .topicsBadgeNew(newCount))
        }
    }
}
