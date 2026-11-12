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

    /// A milestone's length the way a person says it: 7 days is a week, 30 a month.
    static func name(for days: Int) -> StreakMilestoneName {
        switch days {
        case 7: .weeks(1)
        case 14: .weeks(2)
        case 30: .month
        case let days where days > 0 && days.isMultiple(of: daysPerYear): .years(days / daysPerYear)
        default: .days(days)
        }
    }

    /// The milestone stem on the streak sheet: six milestones around the next one,
    /// up to three before it and two after. A milestone the couple reached in an
    /// earlier streak stays marked, because it follows the longest streak.
    static func stem(currentCount: Int, longestCount: Int, visibleCount: Int = 6) -> StreakStem {
        let upcoming = next(after: currentCount)
        var values: [Int] = []
        var last = 0
        while last < upcoming {
            last = next(after: last)
            values.append(last)
        }
        let upcomingIndex = values.count - 1
        while values.count < max(visibleCount, upcomingIndex + 3) {
            last = next(after: last)
            values.append(last)
        }
        let start = max(0, min(upcomingIndex - 3, values.count - visibleCount))
        let window = Array(values[start..<(start + visibleCount)])
        let line = StemLine(milestones: window, startDays: start > 0 ? values[start - 1] : 0)
        let lastReached = previous(atOrBelow: currentCount)

        let nodes = window.map { days in
            let state: StreakStem.Node.State
            if days <= currentCount {
                state = .bloomed
            } else if days == upcoming {
                state = .opening(progress: Double(currentCount - lastReached) / Double(upcoming - lastReached))
            } else if days <= longestCount {
                state = .bloomedBefore
            } else {
                state = .bud
            }
            return StreakStem.Node(days: days, state: state)
        }
        return StreakStem(
            nodes: nodes,
            next: upcoming,
            daysToNext: upcoming - currentCount,
            growth: line.position(of: currentCount),
            record: longestCount > currentCount
                ? StreakStem.Record(days: longestCount, position: line.position(of: longestCount))
                : nil
        )
    }
}

/// Where a day count sits along the stem. 0 is the left end, which stands for the
/// milestone before the window, and 1 the right end. Node `i` of `n` sits at the
/// centre of its column, `(i + 0.5) / n`, and counts between two nodes fall on a
/// straight line between them.
private nonisolated struct StemLine {
    let milestones: [Int]
    let startDays: Int

    func position(of count: Int) -> Double {
        var lower = (days: startDays, position: 0.0)
        for (index, days) in milestones.enumerated() {
            let position = (Double(index) + 0.5) / Double(milestones.count)
            if count <= days {
                let fraction = Double(count - lower.days) / Double(days - lower.days)
                return lower.position + (position - lower.position) * min(max(fraction, 0), 1)
            }
            lower = (days, position)
        }
        return 1
    }
}

/// A milestone's length the way a person says it.
nonisolated enum StreakMilestoneName: Equatable, Sendable {
    case days(Int), weeks(Int), month, years(Int)
}

/// The streak sheet's row of milestones on a growing stem. Positions run from 0 at
/// the stem's left end to 1 at its right end.
nonisolated struct StreakStem: Equatable, Sendable {
    struct Node: Equatable, Identifiable, Sendable {
        enum State: Equatable, Sendable {
            /// The current streak reached it.
            case bloomed
            /// The next milestone, with how far the streak has come from the one before, 0 to 1.
            case opening(progress: Double)
            /// An earlier streak reached it, the current one has not yet.
            case bloomedBefore
            case bud
        }

        let days: Int
        let state: State
        var id: Int { days }
    }

    struct Record: Equatable, Sendable {
        let days: Int
        let position: Double
    }

    let nodes: [Node]
    let next: Int
    let daysToNext: Int
    /// Where the current streak sits along the stem.
    let growth: Double
    /// The longest streak, only while it is longer than the current one.
    let record: Record?
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
