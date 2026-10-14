import Foundation

/// Every game, in the catalog order of `docs/games-plan.md`. The hub lists
/// games in this order. A kind is registered before its game is built, and it
/// shows nowhere until its hub model is in `GamesViewModel.games`.
nonisolated enum GameKind: String, CaseIterable, Codable, Hashable, Sendable {
    // The case order is the hub's catalog order, most popular first.
    case ludo = "ludo"
    case drawAndGuess = "draw_and_guess"
    case connectFour = "connect_four"
    case mindMeld = "mind_meld"
    case dotsAndBoxes = "dots_and_boxes"
    case ultimateTicTacToe = "ultimate_tic_tac_toe"
    case storyChain = "story_chain"
    case exquisiteCorpse = "exquisite_corpse"

    /// The deep link path: `paeonia://games/<path>`, such as `draw-and-guess`.
    var path: String {
        rawValue.replacingOccurrences(of: "_", with: "-")
    }

    /// The game's relay room is `<couple>:<relayChannel>`. The relay's
    /// `ALLOWED_CHANNELS` (`relay/src/ticket.ts`) lists every kind.
    var relayChannel: String {
        rawValue
    }

    /// The game's name, as its card and screen title show it.
    var name: LocalizedStringResource {
        switch self {
        case .ludo: .ludoName
        case .drawAndGuess: .gamesDrawAndGuessName
        case .connectFour: .connectFourName
        case .mindMeld: .mindMeldTitle
        case .dotsAndBoxes: .dotsAndBoxesName
        case .ultimateTicTacToe: .ultimateTicTacToeName
        case .storyChain: .storyChainName
        case .exquisiteCorpse: .exquisiteCorpseName
        }
    }

    init?(path: String) {
        guard let kind = Self.allCases.first(where: { $0.path == path }) else { return nil }
        self = kind
    }
}

/// Who is playing, as every game needs it.
nonisolated struct GameParticipants: Equatable, Sendable {
    var currentUserID: UUID?
    var coupleID: UUID?
    var partnerName: String
    /// The signed-in person's name and photo, for the avatars. They never reset the game.
    var currentName: String
    var currentPhotoAssetID: UUID?
    var partnerPhotoAssetID: UUID?

    init(
        currentUserID: UUID? = nil,
        coupleID: UUID? = nil,
        partnerName: String = "",
        currentName: String = "",
        currentPhotoAssetID: UUID? = nil,
        partnerPhotoAssetID: UUID? = nil
    ) {
        self.currentUserID = currentUserID
        self.coupleID = coupleID
        self.partnerName = partnerName
        self.currentName = currentName
        self.currentPhotoAssetID = currentPhotoAssetID
        self.partnerPhotoAssetID = partnerPhotoAssetID
    }
}
