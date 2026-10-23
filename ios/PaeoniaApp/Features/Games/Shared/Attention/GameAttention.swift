import Foundation

/// What in a game needs this person, named so a change can be told apart from a re-read.
nonisolated struct GameAttention: Equatable, Sendable {
    /// Names the partner's action that made it this person's turn, such as "round 12 drawing sent".
    /// Nil while the game waits for the partner, and nil when this person's own action started the turn.
    var turn: String?
    /// Names the partner's newest action that needs this person without handing them the turn,
    /// such as a wrong guess on their drawing in Draw & Guess. Nil when there is none.
    var partnerStep: String?

    init(turn: String? = nil, partnerStep: String? = nil) {
        self.turn = turn
        self.partnerStep = partnerStep
    }
}

/// Plays a haptic and a sound when a game's `GameAttention` changes while the game is open.
/// A view model feeds it after every read of the game, so the cue does not depend on
/// which view is on screen or whether an animation finished.
@MainActor
final class GameAttentionCue {
    /// The haptics and sounds the cue plays. Injected so tests can record them.
    struct Player {
        var turn: @MainActor () -> Void
        var step: @MainActor () -> Void

        static let live = Player(
            turn: {
                PaeoniaHaptics.gameYourTurn()
                GameSound.nudge.play(volume: 0.6)
            },
            step: {
                PaeoniaHaptics.gamePartnerStep()
                GameSound.nudge.play(volume: 0.35)
            }
        )
    }

    private let player: Player
    /// An update while the app was active has read the game since `init` or `reset()`.
    private(set) var hasRead = false
    /// The newest key of each kind seen. A key that goes away and comes back, such as
    /// when this person's move fails to save, names the same partner move and plays nothing.
    private var lastTurn: String?
    private var lastStep: String?

    init(player: Player = .live) {
        self.player = player
    }

    /// Call after every read of the game. The first update after `init` or `reset()`
    /// only records, so opening a game on your turn plays nothing. While the app is in
    /// the background it records nothing, so a turn that arrived there plays once the
    /// app is back and the game is read again.
    func update(_ attention: GameAttention, isActive: Bool) {
        guard isActive else { return }
        let isNewTurn = attention.turn.map { $0 != lastTurn } ?? false
        let isNewStep = attention.partnerStep.map { $0 != lastStep } ?? false
        lastTurn = attention.turn ?? lastTurn
        lastStep = attention.partnerStep ?? lastStep
        guard hasRead else {
            hasRead = true
            return
        }
        if isNewTurn {
            player.turn()
        } else if isNewStep {
            player.step()
        }
    }

    /// Call when the game screen closes, so opening it again counts as a first read.
    func reset() {
        hasRead = false
        lastTurn = nil
        lastStep = nil
    }
}
