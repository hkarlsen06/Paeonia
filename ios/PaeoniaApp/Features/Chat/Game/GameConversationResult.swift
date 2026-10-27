import Foundation

/// The same complete results the games' histories show, saved with the chat for offline reading.
nonisolated enum GameConversationResult: Equatable, Sendable, Codable, Hashable {
    case mindMeld(RemoteMindMeldHistoryGame)
    case drawAndGuess(RemoteDrawAndGuessHistoryRound, guesses: [String])
    case consensio(RemoteConsensioRound)
    case guessMySpot(RemoteGuessMySpotRound)
    case storyChain(RemoteStoryChainStory)
    case exquisiteCorpse(RemoteExquisiteCorpseFigure)
    case board(GameKind, RemoteBoardGameHistoryGame)

    var date: Date {
        switch self {
        case .mindMeld(let game): game.endedAt ?? game.createdAt
        case .drawAndGuess(let round, _): round.date
        case .consensio(let round): round.guessedAt ?? round.placedAt
        case .guessMySpot(let round): round.guessedAt ?? round.sentAt
        case .storyChain(let story): story.finishedAt ?? story.createdAt
        case .exquisiteCorpse(let figure): figure.finishedAt ?? figure.createdAt
        case .board(_, let game): game.finishedAt
        }
    }

    // A fuller result can replace a locally saved one after opening offline.
    func hash(into hasher: inout Hasher) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        hasher.combine(try? encoder.encode(self))
    }

    enum CodingKeys: String, CodingKey { case kind, result, guesses }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(GameKind.self, forKey: .kind) {
        case .mindMeld: self = .mindMeld(try container.decode(RemoteMindMeldHistoryGame.self, forKey: .result))
        case .drawAndGuess:
            self = .drawAndGuess(
                try container.decode(RemoteDrawAndGuessHistoryRound.self, forKey: .result),
                guesses: try container.decode([String].self, forKey: .guesses)
            )
        case .consensio: self = .consensio(try container.decode(RemoteConsensioRound.self, forKey: .result))
        case .guessMySpot: self = .guessMySpot(try container.decode(RemoteGuessMySpotRound.self, forKey: .result))
        case .storyChain: self = .storyChain(try container.decode(RemoteStoryChainStory.self, forKey: .result))
        case .exquisiteCorpse:
            self = .exquisiteCorpse(try container.decode(RemoteExquisiteCorpseFigure.self, forKey: .result))
        case let kind:
            self = .board(kind, try container.decode(RemoteBoardGameHistoryGame.self, forKey: .result))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mindMeld(let game):
            try container.encode(GameKind.mindMeld, forKey: .kind)
            try container.encode(game, forKey: .result)
        case .drawAndGuess(let round, let guesses):
            try container.encode(GameKind.drawAndGuess, forKey: .kind)
            try container.encode(round, forKey: .result)
            try container.encode(guesses, forKey: .guesses)
        case .consensio(let round):
            try container.encode(GameKind.consensio, forKey: .kind)
            try container.encode(round, forKey: .result)
        case .guessMySpot(let round):
            try container.encode(GameKind.guessMySpot, forKey: .kind)
            try container.encode(round, forKey: .result)
        case .storyChain(let story):
            try container.encode(GameKind.storyChain, forKey: .kind)
            try container.encode(story, forKey: .result)
        case .exquisiteCorpse(let figure):
            try container.encode(GameKind.exquisiteCorpse, forKey: .kind)
            try container.encode(figure, forKey: .result)
        case .board(let kind, let game):
            try container.encode(kind, forKey: .kind)
            try container.encode(game, forKey: .result)
        }
    }
}
