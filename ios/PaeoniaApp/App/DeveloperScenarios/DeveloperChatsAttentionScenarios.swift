#if DEBUG
import SwiftUI

nonisolated extension DeveloperScenario {
    static let chatsAttention = DeveloperScenario(
        "chats-attention", "Chats · attention", "An unread reply to an older story above handled questions", .questions
    ) { _ in DeveloperChatsAttentionHost(answered: false) }

    static let chatsAttentionAnswered = DeveloperScenario(
        "chats-attention-answered", "Chats · answered daily",
        "Themes and unread chats after answering today", .questions
    ) { _ in DeveloperChatsAttentionHost(answered: true) }
}

private struct DeveloperChatsAttentionHost: View {
    let answered: Bool
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

    private var topics: TopicsCardContent {
        let topic = TopicSummary(RemoteTopicSummary(
            topicKey: "travel_and_places", collectionID: coupleID, sortOrder: 1, isPrivate: false,
            titleEN: "Travel and places", subtitleEN: "Places together",
            titleNB: "Reiser og steder", subtitleNB: "Steder sammen",
            totalCount: 21, togetherCount: 10, forYouCount: 0, waitingForPartnerCount: 0
        ))
        return TopicsCardContent(
            topics: [topic], hook: nil, isShown: true, onOpen: {},
            shelfTopics: [topic], newQuestionCount: { _ in 0 }, onOpenTopic: { _ in }
        )
    }

    var body: some View {
        NavigationStack {
            DailyChallengeScreen(
                viewModel: model, conversations: [conversation],
                storyPeople: StoryPeople(currentName: "Alex", partnerName: "Robin"),
                topicsCard: answered ? topics : nil
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
            if answered {
                let snapshot = model.snapshot
                model.snapshot = DailyChallengeSnapshot(
                    currentUserID: snapshot.currentUserID, coupleDayID: snapshot.coupleDayID,
                    questions: snapshot.questions.map { question in
                        var question = question
                        if question.isCurrentDay {
                            question.ownAnswer = DailyQuestionAnswerSummary(id: UUID(), answeredAt: .now)
                        }
                        return question
                    },
                    refreshedAt: snapshot.refreshedAt, anchorTimeZoneID: snapshot.anchorTimeZoneID
                )
            }
        }
    }
}
#endif
