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

    /// Parses a `yyyy-MM-dd` couple-local date into midnight UTC. Returns nil for a
    /// malformed string so the caller can fall back to the memory's `createdAt`. Built
    /// from `DateComponents` rather than a shared `DateFormatter` so it stays
    /// concurrency-safe.
    static func parseLocalDate(_ localDate: String) -> Date? {
        let parts = localDate.split(separator: "-")
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Today's couple-local date as `yyyy-MM-dd`, used to pre-fill the new-memory form.
    /// Uses the device's current calendar/time zone; the user can change the date in the
    /// form, and the backend stores whatever date string is sent.
    static func currentLocalDateString(now: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 2_000
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
