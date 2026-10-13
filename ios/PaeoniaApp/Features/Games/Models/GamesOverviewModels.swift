import Foundation

/// `games:get_games_overview`: what every game and the Games tab share. The
/// couple's settings, and for each game who has it open and this person's last
/// invite. The server reads no clock, so the phone judges the timestamps
/// (`GamePresence.isFresh`, `GameInviteState.make`).
nonisolated struct RemoteGamesOverview: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// Nil until the couple finished setup.
    let settings: RemoteGameSettings?
    /// One entry per game that has a presence row or an invite. A game with
    /// neither is left out.
    let presence: [RemoteGamePresence]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case settings
        case presence
    }

    func presence(for kind: GameKind) -> RemoteGamePresence? {
        presence.first { $0.kind == kind }
    }
}

nonisolated struct RemoteGamePresence: Codable, Equatable, Sendable {
    let kind: GameKind
    let myLastSeenAt: Date?
    let partnerLastSeenAt: Date?
    /// This person's last "Tell [Name] you want to play" for this game.
    let lastInviteAt: Date?

    enum CodingKeys: String, CodingKey {
        case kind
        case myLastSeenAt = "my_last_seen_at"
        case partnerLastSeenAt = "partner_last_seen_at"
        case lastInviteAt = "last_invite_at"
    }
}
