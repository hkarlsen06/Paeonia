import Foundation

/// Mind Meld's own message on its relay room. Each phone sends whether its
/// person is typing in the open round, and again when the partner arrives. Nothing
/// in it is saved, and it never carries letters. Words go through Convex only.
nonisolated struct MindMeldLiveMessage: GameLiveMessage, Equatable {
    static let game = "mind_meld"

    /// The round the sender is in. The receiver ignores any other round.
    let roundNumber: Int
    let isTyping: Bool
}
