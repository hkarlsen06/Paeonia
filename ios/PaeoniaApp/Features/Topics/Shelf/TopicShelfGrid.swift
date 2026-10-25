import SwiftUI

/// Every topic as a tactile card, two across on iPhone, in the order given. The Topics
/// shelf and the calm Questions tab both show it.
struct TopicShelfGrid: View {
    let topics: [TopicSummary]
    let newQuestionCount: (String) -> Int
    let onOpenTopic: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: PaeoniaSpacing.space12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: PaeoniaSpacing.space12) {
            ForEach(topics) { topic in
                Button {
                    onOpenTopic(topic.id)
                } label: {
                    TopicShelfCard(topic: topic, newCount: newQuestionCount(topic.id))
                }
                .buttonStyle(.paeoniaPressableCard)
                .accessibilityIdentifier("topics.card.\(topic.id)")
            }
        }
    }
}
