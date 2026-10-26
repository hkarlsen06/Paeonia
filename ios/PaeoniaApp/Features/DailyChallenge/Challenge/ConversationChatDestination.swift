import Foundation

/// A memory's or a story's chat, read from the phone before it is pushed.
struct ConversationChatDestination: Hashable, Identifiable {
    let id: UUID
    let viewModel: ThreadChatViewModel
    /// The story when this is a story's chat.
    let story: Story?

    init(conversation: SubjectConversation, viewModel: ThreadChatViewModel) {
        id = conversation.id
        self.viewModel = viewModel
        if case let .story(story) = conversation.subject {
            self.story = story
        } else {
            story = nil
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
