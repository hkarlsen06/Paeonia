import Foundation

/// Draw & Guess's own message on its relay room. The guesser's phone sends the
/// whole guess screen each time it changes, and again when the drawer arrives,
/// so the drawer can watch the guesser think. Nothing in it is saved. The
/// guesses themselves still go through Convex.
nonisolated struct DrawAndGuessLiveMessage: GameLiveMessage, Equatable {
    static let game = "draw_and_guess"

    /// The guesser's replay of the finished drawing.
    struct Replay: Codable, Equatable, Sendable {
        /// Replay seconds shown when the message was sent.
        var time: TimeInterval
        /// 1 is the drawn pace, `DrawAndGuessReplayClock.fastForwardRate` while held.
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
}
