import SwiftUI

/// Every topic on the Questions tab while nothing waits for this person, in place of
/// the Topics card, so one tap opens a topic. The heading opens the Topics shelf.
struct TopicsShelfSection: View {
    let content: TopicsCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Button(action: content.onOpen) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("questions.topicsHeading")

            TopicShelfGrid(
                topics: content.shelfTopics,
                newQuestionCount: content.newQuestionCount,
                onOpenTopic: content.onOpenTopic
            )
        }
    }
}
