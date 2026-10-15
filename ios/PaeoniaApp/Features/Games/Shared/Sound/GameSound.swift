import Foundation

/// The games' sound effects. Each one is a file, or a few numbered variants, named
/// `GameSound<rawValue><n>.caf` in Resources/GameSounds. `ios/Scripts/game-sounds.swift`
/// makes them.
nonisolated enum GameSound: String, CaseIterable, Sendable {
    /// A wooden tap for picking something: a tile, a word, a board.
    case tap = "Tap"
    /// A tiny click for counting up and for sliding between choices.
    case tick = "Tick"
    /// A turn or a drawing sent off.
    case send = "Send"
    /// Something from the partner arrived.
    case nudge = "Nudge"
    /// The answer is out.
    case chime = "Chime"
    /// Somebody won, or the two of you matched.
    case win = "Win"
    /// A small extra: a speed bonus, a dare word used.
    case bonus = "Bonus"
    /// A draw or a miss. Gentle, because losing to your partner is fine.
    case soft = "Soft"
    /// A guess that was not it, or a move that can't be made.
    case wrong = "Wrong"
    /// A line or a mark placed on the board.
    case mark = "Mark"
    /// A box or a small board claimed.
    case stamp = "Stamp"
    case ludoDieKnock = "LudoDieKnock"
    case ludoDieSettle = "LudoDieSettle"
    case ludoStep = "LudoStep"
    case ludoCapture = "LudoCapture"
    case ludoHome = "LudoHome"
    case connectFourDrop = "ConnectFourDrop"
    /// A fold of paper laid flat.
    case fold = "Fold"
    /// A card flipped over.
    case flip = "Flip"
    /// A page turned.
    case page = "Page"

    /// Plays the sound. `volume` from 0 to 1 scales it, usually with the strength of the
    /// haptic it goes with.
    func play(volume: Double = 1) {
        GameSoundPlayer.shared.play(self, volume: Float(volume))
    }
}
