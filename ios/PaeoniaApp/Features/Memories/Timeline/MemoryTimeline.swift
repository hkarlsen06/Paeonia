import Foundation

/// One day's worth of memories in the timeline, newest day first. The `dayStartUTC`
/// is midnight of `localDate` in UTC so the header reads the couple-local day exactly,
/// regardless of where the viewer currently is (same convention as Daily history).
nonisolated struct MemoryTimelineDay: Identifiable, Equatable, Sendable {
    let localDate: String
    let dayStartUTC: Date
    let memories: [MemoryRecord]

    var id: String { localDate }
}

/// One month section of the timeline, newest month first. `monthStartUTC` is midnight
/// UTC on the first of the month, so the header formats the stored month exactly.
nonisolated struct MemoryTimelineMonth: Identifiable, Equatable, Sendable {
    /// `yyyy-MM`.
    let id: String
    let monthStartUTC: Date
    let memories: [MemoryRecord]
}

/// Pure grouping for the Memories timeline. Kept out of the view model and views so the
/// ordering and date bucketing can be unit-tested directly.
nonisolated enum MemoryTimeline {
    /// Groups visible memories by their couple-local `memoryDate`, newest day first, and
    /// orders each day's memories newest-created first (ties broken by id for stability).
    /// Hidden, removed, or locally pending-delete memories are dropped so a just-deleted
    /// memory leaves the timeline immediately.
    static func grouped(_ records: [MemoryRecord]) -> [MemoryTimelineDay] {
        let visible = records.filter(isVisible)

        let byDay = Dictionary(grouping: visible) { $0.snapshot.memoryDate }

        return byDay
            .map { localDate, dayRecords in
                MemoryTimelineDay(
                    localDate: localDate,
                    dayStartUTC: parseLocalDate(localDate)
                        ?? dayRecords.first?.snapshot.createdAt
                        ?? .distantPast,
                    memories: dayRecords.sorted(by: isOrderedBefore)
                )
            }
            .sorted { $0.localDate > $1.localDate }
    }

    /// Folds already ordered days into month sections, keeping the day order. A long
    /// timeline then shows which month you're scrolling through.
    static func months(_ days: [MemoryTimelineDay]) -> [MemoryTimelineMonth] {
        var months: [MemoryTimelineMonth] = []
        for day in days {
            let monthID = String(day.localDate.prefix(7))
            if let last = months.last, last.id == monthID {
                months[months.count - 1] = MemoryTimelineMonth(
                    id: monthID,
                    monthStartUTC: last.monthStartUTC,
                    memories: last.memories + day.memories
                )
            } else {
                months.append(
                    MemoryTimelineMonth(
                        id: monthID,
                        monthStartUTC: parseLocalDate("\(monthID)-01") ?? day.dayStartUTC,
                        memories: day.memories
                    )
                )
            }
        }
        return months
    }

    /// Whether a memory should show in the timeline. Excludes anything hidden/removed by
    /// moderation or marked for deletion locally before its delete has synced.
    private static func isVisible(_ record: MemoryRecord) -> Bool {
        record.snapshot.deletedAt == nil
            && record.snapshot.moderationStatus == .visible
            && record.syncStatus != .pendingDelete
    }

    /// Newest-created first within a day, with the memory id as a stable tie-breaker so
    /// two memories created in the same instant keep a deterministic order.
    private static func isOrderedBefore(_ lhs: MemoryRecord, _ rhs: MemoryRecord) -> Bool {
        if lhs.snapshot.createdAt != rhs.snapshot.createdAt {
            return lhs.snapshot.createdAt > rhs.snapshot.createdAt
        }
        return lhs.snapshot.memoryID.uuidString > rhs.snapshot.memoryID.uuidString
    }

    /// Parses a `yyyy-MM-dd` couple-local date into midnight UTC, for display with the
    /// UTC `MemoryDateStyle` formats. Returns nil for a malformed string so the caller
    /// can fall back to the memory's `createdAt`.
    static func parseLocalDate(_ localDate: String) -> Date? {
        date(fromLocalDate: localDate, timeZone: .gmt, hour: 0)
    }

    /// The `yyyy-MM-dd` string for the day `date` falls on in `timeZone`. Always read
    /// with the Gregorian calendar: the backend `date` column is Gregorian, and a
    /// person whose phone uses the Buddhist or Islamic calendar must not save year 2569
    /// or 1448.
    static func localDateString(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 2_000,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    /// The instant a date picker should show for a stored `yyyy-MM-dd`: noon of that day
    /// in `timeZone`. Noon keeps the day stable across daylight saving changes, and
    /// `localDateString(for:timeZone:)` turns it back into the same string. Using
    /// `parseLocalDate` here instead would move the date back a day for anyone west of
    /// UTC, because UTC midnight is still the previous evening there.
    static func pickerDate(forLocalDate localDate: String, timeZone: TimeZone = .current) -> Date? {
        date(fromLocalDate: localDate, timeZone: timeZone, hour: 12)
    }

    private static func date(fromLocalDate localDate: String, timeZone: TimeZone, hour: Int) -> Date? {
        let parts = localDate.split(separator: "-")
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }
}
