import Foundation

/// When a Lock Screen timeline needs another entry without asking the server.
/// Entries are free. Reloads cost the widget's daily budget, the same budget
/// the partner's pushes need, so the timeline never reloads just to check.
nonisolated enum LockScreenTimeline {
    /// Midnights scheduled ahead. Only the calendar changes the widgets on its
    /// own, so a full timeline reloads about once a week. Pushes, and the app as
    /// it leaves the foreground, bring every other change.
    static let daysAhead = 7
    /// Reload sooner while there is nothing to show. A first fetch that runs out
    /// of time would otherwise leave a new widget empty for a week.
    static let emptyReloadInterval: TimeInterval = 15 * 60

    /// Now, the next `daysAhead` local midnights, and the end of the couple's
    /// day. Days together and countdowns change at midnight. Streak and
    /// question flags reset when the couple's day ends.
    static func entryDates(for snapshot: LockScreenSnapshot?, now: Date, calendar: Calendar) -> [Date] {
        var dates = [now]
        var day = calendar.startOfDay(for: now)
        for _ in 0..<daysAhead {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            dates.append(next)
            day = next
        }
        if let endsAt = snapshot?.coupleDay?.endsAt, endsAt > now {
            dates.append(endsAt)
        }
        return Array(Set(dates)).sorted()
    }

    /// When to rebuild the timeline: after its last entry, or soon while there
    /// is nothing to show.
    static func reloadDate(for snapshot: LockScreenSnapshot?, entryDates: [Date], now: Date) -> Date {
        guard snapshot != nil, let last = entryDates.last, last > now else {
            return now.addingTimeInterval(emptyReloadInterval)
        }
        return last
    }
}
