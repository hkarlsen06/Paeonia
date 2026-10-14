import Foundation

/// How one disc falls: gravity down to its cell, then two damped bounces. Pure,
/// so the timing is testable and the screen can ask how long a drop takes.
///
/// Heights are in cells above the disc's resting cell. Times are seconds since
/// the move arrived. A partner's disc first hovers over its column and fades in.
nonisolated struct ConnectFourDropMotion: Equatable {
    nonisolated struct Bounce: Equatable {
        let start: TimeInterval
        let duration: TimeInterval
        /// The top of the hop, in cells above the cell.
        let peak: Double
    }

    /// Cells per second squared. A drop from the lane to the bottom row takes 0.45 seconds.
    static let gravity = 62.0
    static let shortestFall: TimeInterval = 0.25
    static let longestFall: TimeInterval = 0.45
    /// How long the partner's disc hovers over its column before it drops.
    static let partnerHover: TimeInterval = 0.25
    static let partnerFadeIn: TimeInterval = 0.15

    /// How far the disc starts above its cell, in cells.
    let distance: Double
    let hoverDuration: TimeInterval
    let fadeInDuration: TimeInterval
    let fallDuration: TimeInterval
    let bounces: [Bounce]

    init(distance: Double, hover: TimeInterval = 0, fadeIn: TimeInterval = 0) {
        let fall = min(Self.longestFall, max(Self.shortestFall, (2 * distance / Self.gravity).squareRoot()))
        let firstPeak = min(0.3, max(0.08, 0.05 * distance))
        var bounces: [Bounce] = []
        var start = hover + fall
        for peak in [firstPeak, firstPeak * 0.4] {
            let duration = 2 * (2 * peak / Self.gravity).squareRoot()
            bounces.append(Bounce(start: start, duration: duration, peak: peak))
            start += duration
        }
        self.init(
            distance: distance,
            hoverDuration: hover,
            fadeInDuration: fadeIn,
            fallDuration: fall,
            bounces: bounces
        )
    }

    private init(
        distance: Double,
        hoverDuration: TimeInterval,
        fadeInDuration: TimeInterval,
        fallDuration: TimeInterval,
        bounces: [Bounce]
    ) {
        self.distance = distance
        self.hoverDuration = hoverDuration
        self.fadeInDuration = fadeInDuration
        self.fallDuration = fallDuration
        self.bounces = bounces
    }

    /// Reduce Motion: the disc fades in at its cell and never falls.
    static func reduced(fadeIn: TimeInterval) -> ConnectFourDropMotion {
        ConnectFourDropMotion(
            distance: 0,
            hoverDuration: 0,
            fadeInDuration: fadeIn,
            fallDuration: 0,
            bounces: []
        )
    }

    /// When the disc first touches its cell.
    var landingTime: TimeInterval { hoverDuration + fallDuration }

    /// When the disc has stopped moving.
    var totalDuration: TimeInterval {
        let settled = bounces.last.map { $0.start + $0.duration } ?? landingTime
        return max(fadeInDuration, settled)
    }

    /// How far above its cell the disc is, in cells.
    func height(at elapsed: TimeInterval) -> Double {
        if elapsed < hoverDuration { return distance }
        let fallen = elapsed - hoverDuration
        if fallen < fallDuration {
            let fraction = fallen / fallDuration
            return distance * (1 - fraction * fraction)
        }
        for bounce in bounces where elapsed >= bounce.start && elapsed < bounce.start + bounce.duration {
            let fraction = (elapsed - bounce.start) / bounce.duration
            return bounce.peak * 4 * fraction * (1 - fraction)
        }
        return 0
    }

    func opacity(at elapsed: TimeInterval) -> Double {
        guard fadeInDuration > 0 else { return 1 }
        return min(1, max(0, elapsed / fadeInDuration))
    }
}

nonisolated enum ConnectFourClock {
    /// Sleeps until a date. Returns at once for a date in the past.
    static func sleep(until date: Date) async {
        let wait = date.timeIntervalSinceNow
        guard wait > 0 else { return }
        try? await Task.sleep(for: .seconds(wait))
    }
}
