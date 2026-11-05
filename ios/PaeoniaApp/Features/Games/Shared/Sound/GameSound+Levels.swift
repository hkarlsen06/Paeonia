/// Bundled files share one loudness target. These levels describe their role in the app.
/// See docs/game-audio.md before adding sounds or changing the balance.
nonisolated enum GameSoundLevel: Double, Sendable {
    case subtle = 0.3
    case interaction = 0.5
    case event = 0.7
}

nonisolated extension GameSound {
    var level: GameSoundLevel {
        switch self {
        case .tick, .ludoStep:
            .subtle
        case .tap, .mark, .ludoDieKnock, .ludoDieSettle, .connectFourDrop,
             .fold, .flip, .page, .piccanteLift, .piccanteSniff, .piccanteHide:
            .interaction
        case .send, .nudge, .chime, .win, .bonus, .soft, .wrong, .stamp,
             .ludoCapture, .ludoHome, .piccanteBite, .piccanteBurn, .piccanteSameOne:
            .event
        }
    }
}
