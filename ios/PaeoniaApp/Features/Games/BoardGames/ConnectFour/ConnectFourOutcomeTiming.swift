import CoreGraphics
import Foundation

/// Where the result highlight is. The board never stores it as a state machine
/// of timers. It stores the date the highlight started and draws every frame
/// from the seconds since then.
nonisolated enum ConnectFourOutcomeStage: Equatable {
    case idle
    /// The highlight plays from this date. A date in the future waits for a
    /// disc that is still falling.
    case playing(Date)
    /// The highlight is on screen and nothing moves.
    case settled

    var startDate: Date? {
        if case let .playing(date) = self { return date }
        return nil
    }
}

/// The beats of the result highlight, as pure functions of the seconds since it
/// started. The winning cells light up 0.08 seconds apart, a line draws through
/// them, the other discs dim, and the petal bloom bursts at 0.55 seconds. A draw
/// only dims the discs and lets them recover.
nonisolated enum ConnectFourOutcomeTiming {
    static let stagger: TimeInterval = 0.08
    static let pulseDuration: TimeInterval = 0.3
    static let lineDuration: TimeInterval = 0.4
    static let veilRise: TimeInterval = 0.2
    /// When the bloom (or a draw's soft tap) happens.
    static let bloomDelay: TimeInterval = 0.55
    static let peakScale: CGFloat = 1.12
    /// How much of a dark veil lies over the other discs. 0.6 leaves them at 40%.
    static let winnerVeil = 0.6
    /// A draw dims every disc to 60%.
    static let drawVeil = 0.4
    private static let drawHold: TimeInterval = 0.35
    private static let drawRecovery: TimeInterval = 0.3
    private static let glowFade: TimeInterval = 0.15

    /// 0 until the cell's turn, then 1. The ring and glow fade in with it.
    static func glow(rank: Int, elapsed: TimeInterval) -> Double {
        smooth((elapsed - Double(rank) * stagger) / glowFade)
    }

    /// 1, up to 1.12 and back to 1 during the cell's turn.
    static func scale(rank: Int, elapsed: TimeInterval) -> CGFloat {
        let local = elapsed - Double(rank) * stagger
        guard local > 0, local < pulseDuration else { return 1 }
        return 1 + (peakScale - 1) * CGFloat(sin(Double.pi * local / pulseDuration))
    }

    /// How much of the line is drawn, 0 to 1.
    static func lineProgress(elapsed: TimeInterval) -> Double {
        smooth(elapsed / lineDuration)
    }

    /// The opacity of the dark veil over the discs.
    static func veil(elapsed: TimeInterval, isDraw: Bool) -> Double {
        let rise = smooth(elapsed / veilRise)
        guard isDraw else { return winnerVeil * rise }
        let recovery = smooth((elapsed - drawHold) / drawRecovery)
        return drawVeil * rise * (1 - recovery)
    }

    /// When everything has stopped, so the board can stop redrawing each frame.
    static func settleTime(cellCount: Int, isDraw: Bool, bloomDuration: TimeInterval) -> TimeInterval {
        guard !isDraw else { return max(drawHold + drawRecovery, bloomDelay) }
        let lastLit = Double(max(cellCount - 1, 0)) * stagger + pulseDuration
        return max(lastLit, lineDuration, bloomDelay + bloomDuration)
    }

    /// Eases 0 to 1 and holds at both ends.
    private static func smooth(_ value: Double) -> Double {
        let fraction = min(1, max(0, value))
        return fraction * fraction * (3 - 2 * fraction)
    }
}
