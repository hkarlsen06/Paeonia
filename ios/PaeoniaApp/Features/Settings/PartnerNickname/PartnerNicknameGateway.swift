import Foundation

/// The partner nickname backend function (`backend/convex/partnerNickname.ts`).
nonisolated protocol PartnerNicknameGateway: Sendable {
    /// Saves what this person calls their partner, or clears it with nil. Returns the nickname as
    /// the server stored it.
    func setNickname(_ nickname: String?) async throws -> String?
}

nonisolated struct LivePartnerNicknameGateway: PartnerNicknameGateway {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func setNickname(_ nickname: String?) async throws -> String? {
        let result: SetPartnerNicknameResult = try await client.mutation(
            "partnerNickname:set_partner_nickname",
            args: SetPartnerNicknameRequest(nickname: nickname)
        )
        return result.partnerNickname
    }
}

nonisolated enum PartnerNicknameGatewayFactory {
    static func makeDefault() -> (any PartnerNicknameGateway)? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return nil
        }
        return LivePartnerNicknameGateway(client: client)
    }
}

nonisolated private struct SetPartnerNicknameRequest: Encodable {
    let nickname: String?

    enum CodingKeys: String, CodingKey {
        case nickname = "p_nickname"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // `null` clears the nickname, so it is sent rather than left out.
        try container.encode(nickname, forKey: .nickname)
    }
}

nonisolated private struct SetPartnerNicknameResult: Decodable {
    let partnerNickname: String?

    enum CodingKeys: String, CodingKey {
        case partnerNickname = "partner_nickname"
    }
}
