import Foundation

/// `boardGames:get_board_games`: the caller's board games. A kind the couple
/// has never opened has no entry.
nonisolated struct RemoteBoardGames: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// The server's data epoch (`PAEONIA_DATA_EPOCH`). It changes only after a backup
    /// restore or a hand edit of the games, and then the server's copy wins.
    let dataEpoch: String
    let games: [RemoteBoardGame]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case dataEpoch = "data_epoch"
        case games
    }

    func game(_ kind: GameKind) -> RemoteBoardGame? {
        games.first { $0.kind == kind }
    }

    /// This state with one game added or replaced, such as the answer to a move.
    func replacing(_ game: RemoteBoardGame) -> RemoteBoardGames {
        var games = games.filter { $0.kind != game.kind }
        games.append(game)
        let order = GameKind.allCases
        games.sort { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
        return RemoteBoardGames(
            userID: userID,
            partnerUserID: partnerUserID,
            coupleID: coupleID,
            dataEpoch: dataEpoch,
            games: games
        )
    }
}

nonisolated enum BoardGameStatus: String, Codable, Sendable {
    case playing
    case finished
}

/// One board game as the server shows it to the caller. The server stores only
/// the moves. The board, whose turn it is and the outcome come from replaying
/// them with the game's rules.
nonisolated struct RemoteBoardGame: Codable, Equatable, Sendable {
    let id: UUID
    let kind: GameKind
    let gameNumber: Int
    let status: BoardGameStatus
    /// Goes up by one with every move and every rematch. A move names the
    /// version it was made on, and a stale one is refused.
    let version: Int
    /// Player one of the current game.
    let firstUserID: UUID
    let moves: [Int]
    /// Nil once the game is finished.
    let turnUserID: UUID?
    /// Nil for a draw and while playing.
    let winnerUserID: UUID?
    let winLine: [Int]
    let stake: String?
    let stakeByUserID: UUID?
    /// Ludo only: the piece color of each player, always two different ones.
    /// Nil in the other board games.
    let myColor: LudoColor?
    let partnerColor: LudoColor?
    /// The hidden photo of a Dots and Boxes game, while its memory is visible.
    let photoMediaAssetID: UUID?
    let myWins: Int
    let partnerWins: Int
    let draws: Int
    let gamesFinished: Int
    /// The last finished game, kept after a rematch so a partner who missed
    /// its ending can see it.
    let previous: RemoteBoardGameEnding?
    let startedAt: Date
    let finishedAt: Date?
    let turnStartedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case gameNumber = "game_number"
        case status
        case version
        case firstUserID = "first_user_id"
        case moves
        case turnUserID = "turn_user_id"
        case winnerUserID = "winner_user_id"
        case winLine = "win_line"
        case stake
        case stakeByUserID = "stake_by_user_id"
        case myColor = "my_color"
        case partnerColor = "partner_color"
        case photoMediaAssetID = "photo_media_asset_id"
        case myWins = "my_wins"
        case partnerWins = "partner_wins"
        case draws
        case gamesFinished = "games_finished"
        case previous
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case turnStartedAt = "turn_started_at"
        case updatedAt = "updated_at"
    }

    /// True when this is an older picture of the same row than `other`. The
    /// version only goes up, so a live update that raced a newer read loses.
    func isOlder(than other: RemoteBoardGame) -> Bool {
        id == other.id && version < other.version
    }
}

/// A finished game, as `previous` keeps it.
nonisolated struct RemoteBoardGameEnding: Codable, Equatable, Sendable {
    let gameNumber: Int
    let firstUserID: UUID
    let moves: [Int]
    let winnerUserID: UUID?
    let winLine: [Int]
    let stake: String?
    let photoMediaAssetID: UUID?
    let finishedAt: Date

    enum CodingKeys: String, CodingKey {
        case gameNumber = "game_number"
        case firstUserID = "first_user_id"
        case moves
        case winnerUserID = "winner_user_id"
        case winLine = "win_line"
        case stake
        case photoMediaAssetID = "photo_media_asset_id"
        case finishedAt = "finished_at"
    }
}

/// `boardGames:get_board_game_history`: one page of finished games of one
/// kind, newest first.
nonisolated struct RemoteBoardGameHistoryPage: Codable, Equatable, Sendable {
    let games: [RemoteBoardGameHistoryGame]
    /// The cursor for the next page. Nil on the last page.
    let nextBeforeGameNumber: Int?

    enum CodingKeys: String, CodingKey {
        case games
        case nextBeforeGameNumber = "next_before_game_number"
    }
}

/// A finished game, with every move, so it can be watched again.
nonisolated struct RemoteBoardGameHistoryGame: Codable, Equatable, Sendable, Identifiable {
    let gameNumber: Int
    let firstUserID: UUID
    let moves: [Int]
    /// Nil for a draw.
    let winnerUserID: UUID?
    let winLine: [Int]
    let stake: String?
    let startedAt: Date
    let finishedAt: Date

    var id: Int {
        gameNumber
    }

    enum CodingKeys: String, CodingKey {
        case gameNumber = "game_number"
        case firstUserID = "first_user_id"
        case moves
        case winnerUserID = "winner_user_id"
        case winLine = "win_line"
        case stake
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

/// `boardGames:get_board_game_marks`: both partners' marks, shared by the
/// three games. A partner without a drawn mark uses their initial.
nonisolated struct RemoteBoardGameMarks: Codable, Equatable, Sendable {
    let userID: UUID
    let mine: RemoteBoardGameMark?
    let partner: RemoteBoardGameMark?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mine
        case partner
    }
}

nonisolated struct RemoteBoardGameMark: Codable, Equatable, Sendable {
    /// Base64 `PKDrawing` data.
    let drawing: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case drawing
        case updatedAt = "updated_at"
    }
}
