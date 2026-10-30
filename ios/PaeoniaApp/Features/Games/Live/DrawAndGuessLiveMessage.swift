import Foundation

/// Temporary guess screens and reactions in the game's relay room.
nonisolated enum DrawAndGuessLiveMessage: GameLiveMessage, Equatable {
    static let game = "draw_and_guess"

    case guessScreen(DrawAndGuessGuessScreenMessage)
    case reaction(round: UUID, reaction: DrawAndGuessLiveReaction)
}

nonisolated struct DrawAndGuessGuessScreenMessage: Codable, Equatable, Sendable {
    /// The guesser's replay of the finished drawing.
    struct Replay: Codable, Equatable, Sendable {
        /// Replay seconds shown when the message was sent.
        var time: TimeInterval
        /// 1 is the drawn pace, `GameReplayClock.fastForwardRate` while held.
        var rate: Double
    }

    /// The round the guesser is on. The drawer ignores any other round.
    var round: UUID
    /// One entry per answer slot, in order: the letter placed there, or nil for
    /// an empty slot and for the gap between words.
    var letters: [String?]
    /// The full word in the slots was wrong, and the tiles are going back.
    var isWrong: Bool
    /// Nil while the guesser looks at the live canvas, or the drawing is still loading.
    var replay: Replay?
    /// The answer slot indexes filled by "Show a letter", including gaps in the indexing.
    var hintedIndexes: [Int] = []
}
