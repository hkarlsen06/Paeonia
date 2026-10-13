import Foundation

/// How the couple scores games they play. The server keeps every total whatever
/// the style, so the style only changes what the app shows.
nonisolated enum GamePlayStyle: String, Codable, CaseIterable, Sendable {
    /// Each partner has their own score and there is a winner.
    case against
    /// One score for the couple.
    case together
}

/// The language of game content such as words and decoy letters. It is the same
/// for both partners, whatever language each partner's app is in.
typealias GameLanguage = DrawAndGuessLanguage

nonisolated extension GameLanguage {
    /// The app language to preselect in setup: the first of the phone's preferred
    /// languages that the games support, otherwise English.
    static func preferred(from identifiers: [String] = Locale.preferredLanguages) -> GameLanguage {
        for identifier in identifiers {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
            // Norwegian Bokmal is `nb`. `no` and `nn` are the same written language for games.
            if code == "nb" || code == "no" || code == "nn" {
                return .nb
            }
            if code == "en" {
                return .en
            }
        }
        return .en
    }

    /// The language the app's own text is in.
    static var app: GameLanguage {
        preferred(from: Bundle.main.preferredLocalizations)
    }

    /// The language to name above the guesser's answer, or nil when it is the
    /// app's language anyway. A custom word is in whatever language the drawer
    /// typed, so it gets no line.
    static func guessNotice(
        game: GameLanguage,
        app: GameLanguage,
        difficulty: DrawAndGuessDifficulty
    ) -> GameLanguage? {
        difficulty == .custom || game == app ? nil : game
    }
}

/// `games:get_game_settings`, and the `settings` part of `games:get_draw_and_guess`.
nonisolated struct RemoteGameSettings: Codable, Equatable, Sendable {
    let coupleID: UUID
    let playStyle: GamePlayStyle
    let language: GameLanguage
    let updatedByUserID: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case playStyle = "play_style"
        case language
        case updatedByUserID = "updated_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
