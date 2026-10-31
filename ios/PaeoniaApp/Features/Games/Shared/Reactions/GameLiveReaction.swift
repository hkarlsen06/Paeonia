import Foundation

nonisolated enum GameLiveReaction: String, Codable, CaseIterable, Sendable {
    case exclamation, question, laugh, love

    var glyph: String {
        switch self {
        case .exclamation: "!"
        case .question: "?"
        case .laugh: "😂"
        case .love: "❤️"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .exclamation: .gamesLiveReactionExcited
        case .question: .gamesLiveReactionConfused
        case .laugh: .gamesLiveReactionLaugh
        case .love: .gamesLiveReactionLove
        }
    }
}

struct GameLiveReactionFlight: Identifiable {
    static let duration: TimeInterval = 2.8

    let id = UUID()
    let reaction: GameLiveReaction
    let start = Date()
    let tilt = Double.random(in: -14...14)
    let drift = Double.random(in: -24...24)
}
