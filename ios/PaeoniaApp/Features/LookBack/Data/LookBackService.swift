import Foundation

/// What `lookBack:get_look_back` returns: today's item, or nil when the couple has nothing old
/// enough, and when the couple's day ends.
nonisolated struct LookBackResponse: Decodable, Equatable, Sendable {
    let item: LookBackItem?
    /// When the couple day of the request ends. The item stays the same until then.
    let endsAt: Date

    enum CodingKeys: String, CodingKey {
        case item
        case endsAt = "ends_at"
    }
}

/// Reads the Home look-back card's item.
nonisolated protocol LookBackServing: Sendable {
    /// The item for the couple day that contains `now`. The server cannot read its own clock in a
    /// query, so the caller passes the time and rounds it down (`LookBackViewModel.requestTime`).
    func fetch(now: Date) async throws -> LookBackResponse
}

nonisolated struct LiveLookBackService: LookBackServing {
    private struct Request: Encodable {
        let now: Date

        enum CodingKeys: String, CodingKey {
            case now = "p_now"
        }
    }

    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func fetch(now: Date) async throws -> LookBackResponse {
        try await client.query("lookBack:get_look_back", args: Request(now: now))
    }
}

/// Used in previews and when no backend client is configured.
nonisolated struct NoOpLookBackService: LookBackServing {
    // swiftlint:disable:next async_without_await
    func fetch(now: Date) async throws -> LookBackResponse {
        LookBackResponse(item: nil, endsAt: now.addingTimeInterval(3_600))
    }
}
