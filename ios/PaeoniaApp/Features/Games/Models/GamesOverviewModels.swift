import Foundation

/// `games:get_games_overview`: what every game and the Games tab share. The
/// couple's settings, and for each game who has it open and this person's last
/// invite. The phone judges the invite time (`GameInviteState.make`).
nonisolated struct RemoteGamesOverview: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// Nil until the couple finished setup.
    let settings: RemoteGameSettings?
    /// One entry per game that either partner has open or has ever opened, or this
    /// person sent an invite for. Other games are left out.
    var presence: [RemoteGamePresence]
    /// The games this person put aside with "Not now" whose turn, result or invite has
    /// not changed since. They count toward no badge and stay out of "Right now".
    var hiddenKinds: [GameKind] = []

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case settings
        case presence
        case hiddenKinds = "hidden_kinds"
    }

    func clearingPresence() -> Self {
        var copy = self
        copy.presence = presence.map {
            var presence = $0
            presence.myPresent = false
            presence.partnerPresent = false
            return presence
        }
        return copy
    }

    func presence(for kind: GameKind) -> RemoteGamePresence? {
        presence.first { $0.kind == kind }
    }
}

nonisolated struct RemoteGamePresence: Codable, Equatable, Sendable {
    let kind: GameKind
    /// This person has the game open on a phone.
    var myPresent: Bool
    /// The partner has the game open.
    var partnerPresent: Bool
    /// This person's last "Tell [Name] you want to play" for this game.
    let lastInviteAt: Date?
    /// When either partner last had the game open. Nil when neither ever opened it.
    var lastPlayedAt: Date?

    enum CodingKeys: String, CodingKey {
        case kind
        case myPresent = "my_present"
        case partnerPresent = "partner_present"
        case lastInviteAt = "last_invite_at"
        case lastPlayedAt = "last_played_at"
    }
}
