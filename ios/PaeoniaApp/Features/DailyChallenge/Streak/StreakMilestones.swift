import Foundation

/// The streak lengths worth celebrating: 3, 7, 14, 30, 50, 100, 200, 365 and 500
/// days, then every full year. Kept rare on purpose, so a celebration still means
/// something.
nonisolated enum StreakMilestones {
    static let fixed = [3, 7, 14, 30, 50, 100, 200, 365, 500]
    private static let daysPerYear = 365

    static func isMilestone(_ count: Int) -> Bool {
        fixed.contains(count) || (count > daysPerYear && count.isMultiple(of: daysPerYear))
    }

    /// The first milestone above `count`.
    static func next(after count: Int) -> Int {
        if let fixedNext = fixed.first(where: { $0 > count }) { return fixedNext }
        return (count / daysPerYear + 1) * daysPerYear
    }

    /// The milestone at or below `count`, or zero below the first one.
    static func previous(atOrBelow count: Int) -> Int {
        var milestone = 0
        while true {
            let candidate = next(after: milestone)
            guard candidate <= count else { return milestone }
            milestone = candidate
        }
    }

    /// How far `count` is from the previous milestone to the next, from 0 to 1.
    static func progress(toward next: Int, from count: Int) -> Double {
        let start = previous(atOrBelow: count)
        guard next > start else { return 1 }
        return Double(count - start) / Double(next - start)
    }

    /// The badge row on the streak sheet: six milestones around the next one. A
    /// badge stays earned after a break, because it follows the longest streak.
    static func badges(currentCount: Int, longestCount: Int, visibleCount: Int = 6) -> [StreakMilestoneBadge] {
        let upcoming = next(after: currentCount)
        var values: [Int] = []
        var last = 0
        while last < upcoming {
            last = next(after: last)
            values.append(last)
        }
        let upcomingIndex = values.count - 1
        // Up to three milestones before the next one and two after it.
        while values.count < max(visibleCount, upcomingIndex + 3) {
            last = next(after: last)
            values.append(last)
        }
        let start = max(0, min(upcomingIndex - 3, values.count - visibleCount))
        return values[start..<(start + visibleCount)].map { milestone in
            StreakMilestoneBadge(
                days: milestone,
                isEarned: milestone <= longestCount,
                isNext: milestone == upcoming
            )
        }
    }
}

nonisolated struct StreakMilestoneBadge: Equatable, Identifiable, Sendable {
    let days: Int
    let isEarned: Bool
    let isNext: Bool

    var id: Int { days }
}

/// Decides when this phone celebrates a milestone. Each phone shows each milestone
/// once per streak. When the streak falls below a milestone (it broke), that
/// milestone can be celebrated again the next time the couple reaches it.
nonisolated enum StreakMilestoneTracker {
    /// The milestone to celebrate at `count`, if any, and the updated set of shown
    /// milestones. A count of zero is ignored: the app shows zero before the streak
    /// has loaded as well as after a break, so it must not reset anything.
    static func claim(count: Int, shown: Set<Int>) -> (shown: Set<Int>, milestone: Int?) {
        guard count > 0 else { return (shown, nil) }
        var kept = shown.filter { $0 <= count }
        guard StreakMilestones.isMilestone(count), !kept.contains(count) else { return (kept, nil) }
        kept.insert(count)
        return (kept, count)
    }

    /// Marks every milestone up to a restored count as shown. A streak bought back
    /// has its own celebration, so the milestones it skips over are not celebrated.
    static func markRestored(upTo count: Int, shown: Set<Int>) -> Set<Int> {
        var updated = shown
        var milestone = StreakMilestones.next(after: 0)
        while milestone <= count {
            updated.insert(milestone)
            milestone = StreakMilestones.next(after: milestone)
        }
        return updated
    }
}
