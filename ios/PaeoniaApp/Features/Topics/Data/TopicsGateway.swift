import Foundation

/// What the person decided when asked to confirm they are 18 or older for the
/// adults-only topic. Saved per relationship.
nonisolated enum AdultTopicsStatus: String, Encodable, Sendable {
    case confirmed
    case hidden
}

/// The topics backend: `backend/convex/topics.ts`. Answers go through the daily
/// answer queue (`DailySubmitAnswerOperationPayload.topicQuestionID`).
nonisolated protocol TopicsGateway: Sendable {
    func loadOverview() async throws -> RemoteTopicsOverview
    func loadTopic(key: String) async throws -> RemoteTopicDetail
    func setSkipped(questionID: UUID, skipped: Bool) async throws
    func setAdultTopicsStatus(_ status: AdultTopicsStatus) async throws
    /// Follows one topic while its screen is open. Ends when the consuming task is cancelled.
    func topicUpdates(key: String) -> AsyncStream<RemoteTopicDetail>
}

nonisolated struct LiveTopicsGateway: TopicsGateway {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    static func live() -> (any TopicsGateway)? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else { return nil }
        return LiveTopicsGateway(client: client)
    }

    func loadOverview() async throws -> RemoteTopicsOverview {
        try await client.query("topics:get_topics_overview")
    }

    func loadTopic(key: String) async throws -> RemoteTopicDetail {
        try await client.query("topics:get_topic", args: TopicKeyRequest(topicKey: key))
    }

    func setSkipped(questionID: UUID, skipped: Bool) async throws {
        try await client.mutation(
            "topics:set_topic_question_skipped",
            args: TopicSkipRequest(questionID: questionID, skipped: skipped)
        )
    }

    func setAdultTopicsStatus(_ status: AdultTopicsStatus) async throws {
        try await client.mutation("topics:set_adult_topics_status", args: AdultTopicsStatusRequest(status: status))
    }

    func topicUpdates(key: String) -> AsyncStream<RemoteTopicDetail> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe("topics:get_topic", args: ["p_topic_key": key], as: RemoteTopicDetail.self)
                for await result in results {
                    if case let .value(detail) = result {
                        continuation.yield(detail)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

nonisolated struct TopicKeyRequest: Encodable {
    let topicKey: String

    enum CodingKeys: String, CodingKey {
        case topicKey = "p_topic_key"
    }
}

nonisolated struct TopicSkipRequest: Encodable {
    let questionID: UUID
    let skipped: Bool

    enum CodingKeys: String, CodingKey {
        case questionID = "p_question_id"
        case skipped = "p_skipped"
    }
}

nonisolated struct AdultTopicsStatusRequest: Encodable {
    let status: AdultTopicsStatus

    enum CodingKeys: String, CodingKey {
        case status = "p_status"
    }
}
