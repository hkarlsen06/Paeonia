import Foundation

/// The `appPresence:*` functions (`backend/convex/appPresence.ts`).
nonisolated protocol PartnerPresenceGateway: Sendable {
    /// A heartbeat while the app is in front, saying whether the drawing is open, or leaving.
    func setInApp(_ isInApp: Bool, isDrawing: Bool) async throws
    /// "Show when I'm here". Returns the setting the server saved.
    func setShowsPresence(_ shows: Bool) async throws -> Bool
    /// Every reading of the presence query for the couple. Nil while the subscription is down,
    /// when nobody can say the partner is still here.
    func readings(coupleID: UUID) -> AsyncStream<PartnerPresenceReading?>
}

nonisolated struct LivePartnerPresenceGateway: PartnerPresenceGateway {
    let client: PaeoniaConvexClient

    func setInApp(_ isInApp: Bool, isDrawing: Bool) async throws {
        try await client.mutation(
            "appPresence:set_app_presence", args: SetAppPresenceRequest(present: isInApp, drawing: isDrawing))
    }

    func setShowsPresence(_ shows: Bool) async throws -> Bool {
        let row: ShowsPresenceRow = try await client.mutation(
            "appPresence:set_shows_presence", args: SetShowsPresenceRequest(shows: shows))
        return row.showsPresence
    }

    func readings(coupleID: UUID) -> AsyncStream<PartnerPresenceReading?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                for await result in live.subscribe("appPresence:get_partner_presence", as: PartnerPresenceRow.self) {
                    switch result {
                    case let .value(row): continuation.yield(row.reading(coupleID: coupleID))
                    case .failure: continuation.yield(nil)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// A build without a backend: nobody is ever here.
nonisolated struct UnavailablePartnerPresenceGateway: PartnerPresenceGateway {
    struct Unavailable: Error {}

    func setInApp(_: Bool, isDrawing _: Bool) throws {
        throw Unavailable()
    }

    func setShowsPresence(_: Bool) throws -> Bool {
        throw Unavailable()
    }

    func readings(coupleID _: UUID) -> AsyncStream<PartnerPresenceReading?> {
        AsyncStream { _ in }
    }
}

extension LivePartnerPresenceGateway {
    static func make() -> any PartnerPresenceGateway {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return UnavailablePartnerPresenceGateway()
        }
        return LivePartnerPresenceGateway(client: client)
    }
}

// MARK: - Wire format

nonisolated private struct SetAppPresenceRequest: Encodable {
    let present: Bool
    let drawing: Bool

    enum CodingKeys: String, CodingKey {
        case present = "p_present"
        case drawing = "p_drawing"
    }
}

nonisolated private struct SetShowsPresenceRequest: Encodable {
    let shows: Bool

    enum CodingKeys: String, CodingKey {
        case shows = "p_shows"
    }
}

nonisolated private struct ShowsPresenceRow: Decodable {
    let showsPresence: Bool

    enum CodingKeys: String, CodingKey {
        case showsPresence = "shows_presence"
    }
}

nonisolated struct PartnerPresenceRow: Decodable, Sendable {
    struct Partner: Decodable, Sendable {
        let games: [GameKind]
        let drawing: Bool
        let chat: ChatPlace?
        let typing: ChatPlace?
    }

    /// A chat as the server names it (`ChatPlace` in `backend/convex/lib/threadSubjects.ts`), with
    /// the fields a thread row names its subject with.
    struct ChatPlace: Decodable, Sendable {
        let kind: String
        let dailyQuestionID: UUID?
        let memoryID: UUID?
        let storyID: UUID?
        let gameKind: GameKind?

        enum CodingKeys: String, CodingKey {
            case kind
            case dailyQuestionID = "daily_question_id"
            case memoryID = "memory_id"
            case storyID = "story_id"
            case gameKind = "game_kind"
        }

        func subject(coupleID: UUID) -> ThreadChatSubject? {
            ThreadChatSubject(
                kind: kind, coupleID: coupleID, dailyQuestionID: dailyQuestionID, memoryID: memoryID,
                storyID: storyID, gameKind: gameKind)
        }
    }

    let showsPresence: Bool
    let partner: Partner?

    enum CodingKeys: String, CodingKey {
        case showsPresence = "shows_presence"
        case partner
    }

    func reading(coupleID: UUID) -> PartnerPresenceReading {
        PartnerPresenceReading(
            showsPresence: showsPresence,
            partner: partner.map { partner in
                PartnerPresence(
                    games: partner.games,
                    isDrawing: partner.drawing,
                    chat: partner.chat?.subject(coupleID: coupleID),
                    typing: partner.typing?.subject(coupleID: coupleID))
            })
    }
}
