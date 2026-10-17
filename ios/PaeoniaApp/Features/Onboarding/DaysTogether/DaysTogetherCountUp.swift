import Foundation

/// The timing of the days together count-up. The number eases out, fast at first and
/// slowing as it lands, and the ticks follow it: one per day for a short count, or
/// evenly spaced through the number for a long one, so they spread out toward the end.
nonisolated struct DaysTogetherCountUp: Equatable {
    /// The longest a count runs, however many days it counts.
    static let maxDuration: TimeInterval = 2.6
    static let maxTicks = 14

    let days: Int
    /// Seconds from 0 to `days`. Zero when there is nothing to count. It grows with the
    /// number's length: about 0.9 s for 1 day, 2 s for 100, capped at `maxDuration`.
    let duration: TimeInterval

    init(days: Int) {
        self.days = max(0, days)
        duration = self.days == 0
            ? 0
            : min(Self.maxDuration, 0.9 + 0.55 * log10(Double(self.days)))
    }

    /// The number shown `elapsed` seconds in.
    func value(at elapsed: TimeInterval) -> Int {
        guard duration > 0, elapsed < duration else {
            return days
        }
        let progress = max(0, elapsed) / duration
        return Int((Self.ease(progress) * Double(days)).rounded(.down))
    }

    /// When each tick plays, in seconds, with its strength from 0 to 1. The landing
    /// itself is not a tick. It gets the payoff.
    var ticks: [(time: TimeInterval, intensity: Double)] {
        let count = min(days, Self.maxTicks)
        guard count > 1 else {
            return []
        }
        return (1..<count).map { index in
            let fraction = Double(index) / Double(count)
            return (duration * Self.inverseEase(fraction), 0.3 + 0.5 * fraction)
        }
    }

    /// Quadratic ease out.
    private static func ease(_ progress: Double) -> Double {
        1 - (1 - progress) * (1 - progress)
    }

    /// The progress at which `ease` reaches `value`.
    private static func inverseEase(_ value: Double) -> Double {
        1 - (1 - value).squareRoot()
    }
}
