import Foundation

/// Guess my spot's own message on its relay room: where the guesser's pin is while
/// they guess, so the sender can watch it land. The guessing phone sends it on every
/// tap and when the sender arrives. Nothing in it is saved.
///
/// It has no field for the real spot, and the sending phone never sends one. The
/// real spot goes through Convex only.
nonisolated struct GuessMySpotLiveMessage: GameLiveMessage, Equatable {
    static let game = "guess_my_spot"

    /// The round being guessed. The receiver ignores any other round.
    let roundID: UUID
    /// Nil before the first tap.
    let guess: GuessMySpotCoordinate?
}
