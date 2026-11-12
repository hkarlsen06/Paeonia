import Foundation

nonisolated protocol RecapServing: Sendable {
    func fetchRecaps() async throws -> [AnniversaryRecap]
    func ensureRecap() async throws -> AnniversaryRecap?
    func fetchMoments(anniversaryDate: String) async throws -> [LookBackItem]
}

nonisolated struct LiveRecapService: RecapServing {
    private struct PageRequest: Encodable {
        let before: String?

        enum CodingKeys: String, CodingKey {
            case before = "p_before"
        }
    }

    private struct Page: Decodable {
        let recaps: [AnniversaryRecap]
        let nextBefore: String?

        enum CodingKeys: String, CodingKey {
            case recaps
            case nextBefore = "next_before"
        }
    }

    private struct MomentsRequest: Encodable {
        let anniversaryDate: String

        enum CodingKeys: String, CodingKey {
            case anniversaryDate = "p_anniversary_date"
        }
    }

    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    /// Every recap, newest first. The server sends them a few at a time.
    func fetchRecaps() async throws -> [AnniversaryRecap] {
        var recaps: [AnniversaryRecap] = []
        var before: String?
        repeat {
            let page: Page = try await client.query("recap:get_recaps", args: PageRequest(before: before))
            recaps += page.recaps
            before = page.nextBefore
        } while before != nil
        return recaps
    }

    func ensureRecap() async throws -> AnniversaryRecap? {
        try await client.action("recap:ensure_anniversary_recap")
    }

    func fetchMoments(anniversaryDate: String) async throws -> [LookBackItem] {
        try await client.query("recap:get_recap_moments", args: MomentsRequest(anniversaryDate: anniversaryDate))
    }
}

nonisolated struct NoOpRecapService: RecapServing {
    // swiftlint:disable async_without_await
    func fetchRecaps() async throws -> [AnniversaryRecap] { [] }
    func ensureRecap() async throws -> AnniversaryRecap? { nil }
    func fetchMoments(anniversaryDate _: String) async throws -> [LookBackItem] { [] }
    // swiftlint:enable async_without_await
}
