import Foundation

nonisolated enum DrawAndGuessLiveReaction: String, Codable, CaseIterable, Sendable {
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
        case .exclamation: .gamesDrawAndGuessLiveReactionExcited
        case .question: .gamesDrawAndGuessLiveReactionConfused
        case .laugh: .gamesDrawAndGuessLiveReactionLaugh
        case .love: .gamesDrawAndGuessLiveReactionLove
        }
    }
}

struct DrawAndGuessReactionFlight: Identifiable {
    static let duration: TimeInterval = 2.8

    let id = UUID()
    let reaction: DrawAndGuessLiveReaction
    let start = Date()
    let tilt = Double.random(in: -14...14)
    let drift = Double.random(in: -24...24)
}
