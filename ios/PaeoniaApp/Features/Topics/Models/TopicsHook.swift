import Foundation

/// The Topics card's line about what's waiting for this person. It never names a
/// private topic (Flirt), because the Questions tab is often open where others see it.
nonisolated enum TopicsHook: Equatable, Sendable {
    /// The partner answered questions in one topic that wait for this person.
    case answeredIn(partner: String, count: Int, topic: String)
    /// The partner answered questions across topics, or in one that isn't named.
    case answeredForYou(partner: String, count: Int)
    case messageIn(topic: String)
    case messageFrom(partner: String)

    static func make(
        overview: [TopicSummary],
        unreadTopicChats: [DailyQuestionThreadSummary],
        partnerName: String
    ) -> TopicsHook? {
        let waiting = overview.filter { $0.forYouCount > 0 }
        let total = waiting.reduce(0) { $0 + $1.forYouCount }
        if total > 0 {
            if waiting.count == 1, let topic = waiting.first, !topic.isPrivate {
                return .answeredIn(partner: partnerName, count: total, topic: topic.title)
            }
            return .answeredForYou(partner: partnerName, count: total)
        }
        guard let chat = unreadTopicChats.first else { return nil }
        if chat.isPrivateTopic != true,
           let topic = overview.first(where: { $0.id == chat.topicKey }),
           !topic.isPrivate {
            return .messageIn(topic: topic.title)
        }
        return .messageFrom(partner: partnerName)
    }

    var text: LocalizedStringResource {
        switch self {
        case let .answeredIn(partner, 1, topic):
            .topicsHookAnsweredOneIn(partner, topic)
        case let .answeredIn(partner, count, topic):
            .topicsHookAnsweredCountIn(partner, count, topic)
        case let .answeredForYou(partner, 1):
            .topicsHookAnsweredOneForYou(partner)
        case let .answeredForYou(partner, count):
            .topicsHookAnsweredCountForYou(partner, count)
        case let .messageIn(topic):
            .topicsHookMessageIn(topic)
        case let .messageFrom(partner):
            .topicsHookMessageFrom(partner)
        }
    }
}
