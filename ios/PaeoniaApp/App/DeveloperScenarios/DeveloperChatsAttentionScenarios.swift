#if DEBUG
import SwiftUI

nonisolated extension DeveloperScenario {
    static let chatsAttention = DeveloperScenario(
        "chats-attention", "Chats · attention", "An unread reply to an older story above handled questions", .questions
    ) { _ in DeveloperChatsAttentionHost() }
}

private struct DeveloperChatsAttentionHost: View {
    @State private var model = DailyChallengeViewModel(service: PreviewDailyChallengeService())
    private let partnerID = UUID()
    private let coupleID = UUID()

    private var conversation: SubjectConversation {
        let posted = Date(timeIntervalSince1970: 1_767_268_800)
        let story = Story(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc") ?? UUID(),
            authorUserID: partnerID, mediaAssetID: UUID(), caption: "Our winter walk", createdAt: posted
        )
        return SubjectConversation(
            subject: .story(story),
            summary: ThreadChatSummary(
                threadID: story.id, coupleID: coupleID, subject: .story(story.id),
                createdAt: posted, updatedAt: .now, lastMessageID: story.id,
                lastMessageAt: .now, lastMessageSenderUserID: partnerID,
                lastMessageBody: "Thinking about this today"
            ),
            isUnread: true
        )
    }

    var body: some View {
        NavigationStack {
            DailyChallengeScreen(
                viewModel: model, conversations: [conversation],
                storyPeople: StoryPeople(currentName: "Alex", partnerName: "Robin")
            )
        }
        .environment(PaeoniaBannerCenter())
        .preferredColorScheme(.dark)
        .task {
            await model.configure(
                participants: DailyChallengeParticipants(
                    currentUserID: PreviewDailyChallengeService.userID, currentDisplayName: "Alex",
                    partnerUserID: partnerID, partnerDisplayName: "Robin"
                )
            )
        }
    }
}
#endif
