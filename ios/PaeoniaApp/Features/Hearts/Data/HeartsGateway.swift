import Foundation

/// The hearts backend functions (`backend/convex/hearts.ts`).
nonisolated protocol HeartsGateway: Sendable {
    /// Adds hearts to what this person has sent. The server runs each operation id
    /// once, so a retry after a lost answer does not send them twice.
    func sendHearts(count: Int, operation: SyncClientOperation) async throws
    /// Tells the server this person was shown the partner's hearts up to `seenTotal`.
    /// The server keeps the larger total, so a retry is safe.
    func markHeartsSeen(seenTotal: Int) async throws
}

nonisolated struct LiveHeartsGateway: HeartsGateway {
    let client: PaeoniaConvexClient

    func sendHearts(count: Int, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "hearts:send_hearts",
            args: SendHeartsRequest(count: count, operation: operation)
        )
    }

    func markHeartsSeen(seenTotal: Int) async throws {
        try await client.mutation("hearts:mark_hearts_seen", args: MarkHeartsSeenRequest(seenTotal: seenTotal))
    }
}

nonisolated private struct SendHeartsRequest: Encodable {
    let count: Int
    let operation: GameClientOperationFields

    init(count: Int, operation: SyncClientOperation) {
        self.count = count
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case count = "p_count"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(count, forKey: .count)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct MarkHeartsSeenRequest: Encodable {
    let seenTotal: Int

    enum CodingKeys: String, CodingKey {
        case seenTotal = "p_seen_total"
    }
}
