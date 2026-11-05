import Foundation

nonisolated enum PiccantePhase: String, Codable, Sendable { case choosing, hiding, biting, finished }

nonisolated struct PiccanteBite: Codable, Equatable, Sendable {
    let tile: Int
    let userID: UUID
    let playAt: Date
    enum CodingKeys: String, CodingKey {
        case tile
        case playAt = "play_at"
        case userID = "user_id"
    }
}

nonisolated struct PiccanteChili: Codable, Equatable, Sendable {
    let tile: Int
    let userID: UUID
    let note: String?
    enum CodingKeys: String, CodingKey {
        case tile, note
        case userID = "user_id"
    }
}

nonisolated struct PiccanteSniff: Codable, Equatable, Sendable {
    let tile: Int
    let hasChili: Bool
    enum CodingKeys: String, CodingKey {
        case tile
        case hasChili = "has_chili"
    }
}

nonisolated struct RemotePiccanteGame: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var gameNumber: Int
    var version: Int
    var starterUserID: UUID
    var turnUserID: UUID?
    var phase: PiccantePhase
    var size: Int?
    var myChili: Int?
    var myNote: String?
    var partnerHidden: Bool
    var mySniff: PiccanteSniff?
    var partnerSniffUsed: Bool
    var bites: [PiccanteBite]
    var chilis: [PiccanteChili]
    var winnerUserID: UUID?
    var loserUserID: UUID?
    var myWins: Int
    var partnerWins: Int
    var gamesFinished: Int
    var startedAt: Date
    var finishedAt: Date?
    enum CodingKeys: String, CodingKey {
        case id, version, phase, size, bites, chilis
        case gameNumber = "game_number"
        case starterUserID = "starter_user_id"
        case turnUserID = "turn_user_id"
        case myChili = "my_chili"
        case myNote = "my_note"
        case partnerHidden = "partner_hidden"
        case mySniff = "my_sniff"
        case partnerSniffUsed = "partner_sniff_used"
        case winnerUserID = "winner_user_id"
        case loserUserID = "loser_user_id"
        case myWins = "my_wins"
        case partnerWins = "partner_wins"
        case gamesFinished = "games_finished"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

nonisolated struct RemotePiccanteState: Codable, Equatable, Sendable {
    let userID: UUID
    let coupleID: UUID
    let partnerUserID: UUID
    let dataEpoch: String
    var game: RemotePiccanteGame?
    var unseenResult: RemotePiccanteGame?
    enum CodingKeys: String, CodingKey {
        case game
        case userID = "user_id"
        case coupleID = "couple_id"
        case partnerUserID = "partner_user_id"
        case dataEpoch = "data_epoch"
        case unseenResult = "unseen_result"
    }
    func isOlder(than other: Self) -> Bool {
        guard dataEpoch == other.dataEpoch, game?.id == other.game?.id else { return false }
        return (game?.version ?? 0) < (other.game?.version ?? 0)
    }
}

nonisolated extension RemotePiccanteGame {
    func preview(hidingResult: Bool) -> Self {
        guard phase == .finished, hidingResult else { return self }
        var box = self
        box.phase = .biting
        box.bites = Array(bites.dropLast())
        box.chilis = []
        box.myChili = nil
        box.myNote = nil
        box.mySniff = nil
        box.winnerUserID = nil
        box.loserUserID = nil
        return box
    }
}
