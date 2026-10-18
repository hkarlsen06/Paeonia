import Foundation

/// Consensio's own message on its relay room: where the guesser's marker is
/// while they guess, so the placer can watch it move. The guessing phone sends it
/// as the finger moves (at most 15 times a second), when the finger lifts, and
/// when the placer arrives. Nothing in it is saved.
///
/// It has no field for the real spot, and the placing phone never sends one. The
/// real spot goes through Convex only.
nonisolated struct ConsensioLiveMessage: GameLiveMessage, Equatable {
    static let game = "consensio"

    /// The round being guessed. The receiver ignores any other round.
    let roundID: UUID
    /// 0 to 100, or nil before the marker is on the line.
    let position: Int?
    /// A finger is on the marker.
    let touching: Bool
}
