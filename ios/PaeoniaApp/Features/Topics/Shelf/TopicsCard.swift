import SwiftUI

/// The card under the daily question on the Questions tab. It opens the Topics shelf,
/// says what the partner answered (`TopicsHook`), and shows the three topics with the
/// most going on. It is quieter than the daily card above it and glows only while
/// something waits for this person.
struct TopicsCard: View {
    let topics: [TopicSummary]
    let hook: TopicsHook?
    let partnerName: String
    let partnerPhotoAssetID: UUID?
    let onOpen: () -> Void

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)

    var body: some View {
        Button(action: onOpen) {
            cardContent
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("questions.topicsCard")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            HStack(alignment: .firstTextBaseline) {
                Text(.topicsCardTitle)
                    .font(PaeoniaTypography.collectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                Spacer(minLength: PaeoniaSpacing.space8)
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }

            hookLine

            if !topics.isEmpty {
                HStack(spacing: PaeoniaSpacing.space8) {
                    ForEach(topics) { topic in
                        chip(topic)
                    }
                }
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape
                .fill(.paeoniaSurfaceSecondary)
                .shadow(color: .paeoniaAccentPrimary.opacity(hook == nil ? 0 : 0.22), radius: 18, y: 6)
        }
        .overlay {
            shape.strokeBorder(
                hook == nil ? Color.paeoniaSurfacePressed : Color.paeoniaAccentPrimary.opacity(0.5),
                lineWidth: hook == nil ? PaeoniaRadius.strokeHairline : PaeoniaRadius.strokeDefault
            )
        }
        .contentShape(shape)
    }

    @ViewBuilder
    private var hookLine: some View {
        if let hook {
            HStack(spacing: PaeoniaSpacing.space8) {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: partnerPhotoAssetID,
                    name: partnerName,
                    tint: .paeoniaPartnerTwo,
                    size: 22
                )
                .accessibilityHidden(true)
                Text(hook.text)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(.topicsCardIdle)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A small tile per topic: its picture and its ring. VoiceOver reads the card's
    /// lines instead.
    private func chip(_ topic: TopicSummary) -> some View {
        let tint = TopicStyle.tint(for: topic.id)
        return VStack(spacing: PaeoniaSpacing.space4) {
            TopicArtwork(topicKey: topic.id, height: 34, playsBeat: false)
                .frame(height: 38)
            HStack(spacing: PaeoniaSpacing.space4) {
                TopicProgressRing(progress: topic.progress, tint: tint, size: 11, lineWidth: 2)
                Text(verbatim: "\(topic.togetherCount)/\(topic.totalCount)")
                    .font(PaeoniaTypography.caption.monospacedDigit())
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .padding(.vertical, PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [tint.opacity(0.32), .paeoniaSurfacePrimary], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}

/// What the Questions tab needs from the topics: the Topics card, the shelf's grid it
/// shows instead while the tab is calm, and the topic questions waiting for this
/// person, which its list shows with the daily ones. `isShown == false` leaves the
/// topics out, such as before they have loaded once.
struct TopicsCardContent {
    /// The few topics the compact card shows.
    let topics: [TopicSummary]
    let hook: TopicsHook?
    let isShown: Bool
    /// Opens the Topics shelf.
    let onOpen: () -> Void
    /// Every topic in the shelf's order, for the grid.
    let shelfTopics: [TopicSummary]
    let newQuestionCount: (String) -> Int
    /// Opens one topic, by key.
    let onOpenTopic: (String) -> Void
    var waitingQuestions: [DailyChallengeQuestion] = []
    /// Every topic's name by key, for the waiting questions' rows.
    var topicTitles: [String: String] = [:]

    func title(of question: DailyChallengeQuestion) -> String? {
        question.topicKey.flatMap { topicTitles[$0] }
    }
}
