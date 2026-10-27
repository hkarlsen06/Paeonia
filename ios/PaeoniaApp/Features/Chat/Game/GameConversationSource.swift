@preconcurrency import ConvexMobile
import CryptoKit
import Foundation

/// A finished creation or round, or one numbered board game in a couple's history.
nonisolated enum GameConversationSource: Hashable, Sendable, Codable, Identifiable, ConvexEncodable {
    case drawAndGuess(UUID)
    case mindMeld(UUID)
    case consensio(UUID)
    case guessMySpot(UUID)
    case storyChain(UUID)
    case exquisiteCorpse(UUID)
    case connectFour(coupleID: UUID, number: Int)
    case dotsAndBoxes(coupleID: UUID, number: Int)
    case ultimateTicTacToe(coupleID: UUID, number: Int)
    case ludo(coupleID: UUID, number: Int)

    var kind: GameKind {
        switch self {
        case .drawAndGuess: .drawAndGuess
        case .mindMeld: .mindMeld
        case .consensio: .consensio
        case .guessMySpot: .guessMySpot
        case .storyChain: .storyChain
        case .exquisiteCorpse: .exquisiteCorpse
        case .connectFour: .connectFour
        case .dotsAndBoxes: .dotsAndBoxes
        case .ultimateTicTacToe: .ultimateTicTacToe
        case .ludo: .ludo
        }
    }

    var id: UUID {
        switch self {
        case .drawAndGuess(let id), .mindMeld(let id), .consensio(let id), .guessMySpot(let id),
            .storyChain(let id), .exquisiteCorpse(let id):
            id
        case .connectFour(let coupleID, let number), .dotsAndBoxes(let coupleID, let number),
            .ultimateTicTacToe(let coupleID, let number), .ludo(let coupleID, let number):
            Self.boardID(coupleID: coupleID, kind: kind, number: number)
        }
    }

    static func board(kind: GameKind, coupleID: UUID, number: Int) -> Self? {
        switch kind {
        case .connectFour: .connectFour(coupleID: coupleID, number: number)
        case .dotsAndBoxes: .dotsAndBoxes(coupleID: coupleID, number: number)
        case .ultimateTicTacToe: .ultimateTicTacToe(coupleID: coupleID, number: number)
        case .ludo: .ludo(coupleID: coupleID, number: number)
        default: nil
        }
    }

    private static func boardID(coupleID: UUID, kind: GameKind, number: Int) -> UUID {
        let key = "game-chat:\(coupleID.uuidString.lowercased()):\(kind.rawValue):\(number)"
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }

    enum CodingKeys: String, CodingKey {
        case kind, id
        case coupleID = "couple_id"
        case gameNumber = "game_number"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(GameKind.self, forKey: .kind)
        switch kind {
        case .drawAndGuess: self = .drawAndGuess(try container.decode(UUID.self, forKey: .id))
        case .mindMeld: self = .mindMeld(try container.decode(UUID.self, forKey: .id))
        case .consensio: self = .consensio(try container.decode(UUID.self, forKey: .id))
        case .guessMySpot: self = .guessMySpot(try container.decode(UUID.self, forKey: .id))
        case .storyChain: self = .storyChain(try container.decode(UUID.self, forKey: .id))
        case .exquisiteCorpse: self = .exquisiteCorpse(try container.decode(UUID.self, forKey: .id))
        case .connectFour, .dotsAndBoxes, .ultimateTicTacToe, .ludo:
            let coupleID = try container.decode(UUID.self, forKey: .coupleID)
            let number = try container.decode(Int.self, forKey: .gameNumber)
            guard number > 0, let source = Self.board(kind: kind, coupleID: coupleID, number: number) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .gameNumber, in: container, debugDescription: "Invalid game number")
            }
            self = source
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .drawAndGuess, .mindMeld, .consensio, .guessMySpot, .storyChain, .exquisiteCorpse:
            try container.encode(id, forKey: .id)
        case .connectFour(let coupleID, let number), .dotsAndBoxes(let coupleID, let number),
            .ultimateTicTacToe(let coupleID, let number), .ludo(let coupleID, let number):
            try container.encode(coupleID, forKey: .coupleID)
            try container.encode(number, forKey: .gameNumber)
        }
    }
}
