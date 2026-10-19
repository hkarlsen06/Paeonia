import SwiftUI

/// Screens pushed on the Questions tab.
enum QuestionsDestination: Hashable {
    /// The Topics shelf.
    case topics
    /// One topic, by key.
    case topic(String)
}

/// The topics on the Questions tab: the shelf, a topic's screen, and the answer
/// session, which shares the daily answer cover (`partnerAnswerQuestion`).
extension MainTabView {
    @ViewBuilder
    func questionsDestination(_ destination: QuestionsDestination) -> some View {
        switch destination {
        case .topics:
            TopicsShelfView(
                viewModel: topicsViewModel,
                onOpenTopic: { questionsPath.append(.topic($0)) }
            )
        case let .topic(key):
            TopicScreen(
                topicKey: key,
                viewModel: topicsViewModel,
                dailyChallenge: dailyChallengeViewModel,
                zoomNamespace: zoomNamespace,
                onAnswer: openPartnerAnswerFlow,
                onOpenChat: openTopicChat
            )
            // Hidden before the chat is pushed, like the Questions tab does, so the
            // bar never shows over the chat's composer.
            .toolbar(dailyChatQuestion == nil ? .visible : .hidden, for: .tabBar)
        }
    }

    func openTopics() {
        selection.wrappedValue = .questions
        questionsPath = [.topics]
    }

    /// A topic question's page, read from the phone first so it opens complete.
    func openTopicChat(_ question: DailyChallengeQuestion) {
        Task {
            await dailyChallengeViewModel.prepareChat(for: question)
            dailyChatQuestion = question
        }
    }

    /// The answer session for a topic question, in the cover the daily partner
    /// questions use.
    func topicAnswerSession(for question: DailyChallengeQuestion) -> some View {
        TopicAnswerSession(
            question: question,
            topics: topicsViewModel,
            dailyChallenge: dailyChallengeViewModel,
            privacySafetyService: dependencies.settingsPrivacyService,
            privacyOperationProvider: dependencies.settingsPrivacyOperationProvider,
            onReportedAndLeft: actions.leftRelationship,
            onClose: { partnerAnswerQuestion = nil }
        )
    }

    /// The Topics card's line, from the overview and the unread topic chats.
    var topicsHook: TopicsHook? {
        topicsViewModel.hook(
            partnerName: dailyChallengeParticipants.partnerName,
            unreadTopicChats: dailyChallengeViewModel.unreadChats.filter { $0.topicKey != nil }
        )
    }

    /// A chat notification for a topic question: today's questions and the history
    /// don't have it, so the topic is read instead.
    func topicChatQuestion(questionID: UUID) async -> DailyChallengeQuestion? {
        guard let topicKey = dailyChallengeViewModel.threadSummariesByQuestionID[questionID]?.topicKey else {
            return nil
        }
        return await topicsViewModel.chatQuestion(questionID: questionID, topicKey: topicKey)
    }
}
