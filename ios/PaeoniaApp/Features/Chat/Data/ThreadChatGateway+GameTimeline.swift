import Foundation

nonisolated struct GameChatTimelineRequest: Encodable {
    let subject: GameChatSubject
    var before: GameChatTimelineCursor?
    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case kind = "p_game_kind"
        case before = "p_before"
        case limit = "p_limit"
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subject.coupleID, forKey: .coupleID)
        try container.encode(subject.kind, forKey: .kind)
        try container.encodeIfPresent(before, forKey: .before)
        try container.encode(ThreadChatMessage.pageSize, forKey: .limit)
    }
}

nonisolated struct GameChatTimelineRow: Decodable {
    let threadID: UUID?
    let messages: [ThreadMessageRow]
    let results: [GameChatResultReference]
    let hasMore: Bool
    let nextBefore: GameChatTimelineCursor?
    enum CodingKeys: String, CodingKey {
        case messages, results
        case threadID = "thread_id"
        case hasMore = "has_more"
        case nextBefore = "next_before"
    }
    func timeline(subject: GameChatSubject) -> GameChatTimeline {
        GameChatTimeline(
            threadID: threadID, messages: messages.compactMap { $0.message(subjectID: subject.id) },
            results: results, hasMore: hasMore, nextBefore: nextBefore)
    }
}

extension LiveThreadChatGateway {
    func loadGameTimeline(subject: GameChatSubject, before: GameChatTimelineCursor?) async throws
        -> GameChatTimeline
    {
        let row: GameChatTimelineRow = try await client.query(
            "gameConversations:get_game_chat_timeline",
            args: GameChatTimelineRequest(subject: subject, before: before))
        return row.timeline(subject: subject)
    }

    nonisolated func liveGameTimeline(subject: GameChatSubject) -> AsyncStream<GameChatTimeline> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let updates = live.subscribe(
                    "gameConversations:get_game_chat_timeline",
                    args: [
                        "p_couple_id": subject.coupleID.uuidString.lowercased(),
                        "p_game_kind": subject.kind.rawValue, "p_limit": Double(ThreadChatMessage.pageSize),
                    ],
                    as: GameChatTimelineRow.self)
                for await update in updates {
                    guard !Task.isCancelled else { break }
                    if case .value(let row) = update { continuation.yield(row.timeline(subject: subject)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
