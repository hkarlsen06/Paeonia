import Foundation

/// One day in the earlier-days list: its answered questions and the chats about memories
/// added or stories posted that day. Identified by the couple's local date string so it stays stable
/// across reloads, and carrying a parsed `date` purely so the divider can format it in
/// the reader's locale.
nonisolated struct DailyChallengeHistoryDay: Identifiable, Equatable, Sendable {
    /// The couple's local date as `yyyy-MM-dd`, e.g. "2026-06-27". Stable identity.
    let localDate: String
    /// Midnight of `localDate` in UTC, for locale-aware formatting in the divider.
    /// Formatting must pin the time zone to UTC so the displayed day never shifts.
    let date: Date
    let rows: [QuestionsTabRow]

    var id: String { localDate }
}

/// Pure grouping for the Questions history: turns the flat, chronological list of
/// answered questions into day groups, newest day first. Kept free of SwiftUI and
/// networking so the ordering rules are easy to unit test.
nonisolated enum DailyChallengeHistory {
    /// Groups the latest answer time in the same shared zone as the conversation rows.
    /// Days and rows are newest first, with UUIDs breaking equal-time ties.
    static func grouped(
        _ questions: [DailyChallengeQuestion],
        timeZone: TimeZone = .gmt
    ) -> [DailyChallengeHistoryDay] {
        Dictionary(grouping: questions) {
            MemoryTimeline.localDateString(for: $0.latestAnswerDate, timeZone: timeZone)
        }
        .map { localDate, dayQuestions in
            DailyChallengeHistoryDay(
                localDate: localDate,
                date: parseLocalDate(localDate) ?? .distantPast,
                rows: dayQuestions.map(QuestionsTabRow.question).sorted(by: QuestionsTabRow.timelineOrder)
            )
        }
        .sorted { $0.localDate > $1.localDate }
    }

    /// The days with the chats about memories and stories from before `today` added under
    /// the day each memory was added or story posted. A day with only those chats gets its
    /// own entry.
    static func adding(
        _ conversations: [SubjectConversation],
        before today: String,
        to days: [DailyChallengeHistoryDay],
        timeZone: TimeZone = .gmt
    ) -> [DailyChallengeHistoryDay] {
        let earlier = Dictionary(grouping: conversations.filter { !$0.isToday(today, timeZone: timeZone) }) {
            MemoryTimeline.localDateString(for: $0.startedAt, timeZone: timeZone)
        }
        guard !earlier.isEmpty else { return days }
        var daysByDate = Dictionary(uniqueKeysWithValues: days.map { ($0.localDate, $0) })
        for (localDate, chats) in earlier {
            let day = daysByDate[localDate]
            let rows = (day?.rows ?? []) + chats.map(QuestionsTabRow.conversation)
            daysByDate[localDate] = DailyChallengeHistoryDay(
                localDate: localDate,
                date: day?.date ?? parseLocalDate(localDate) ?? chats[0].startedAt,
                rows: rows.sorted(by: QuestionsTabRow.timelineOrder)
            )
        }
        return daysByDate.values.sorted { $0.localDate > $1.localDate }
    }

    /// The days without the rows in `ids`. A day left with no rows is dropped, so the
    /// earlier-days list never shows a divider with nothing under it.
    static func removing(_ ids: Set<UUID>, from days: [DailyChallengeHistoryDay]) -> [DailyChallengeHistoryDay] {
        guard !ids.isEmpty else { return days }
        return days.compactMap { day in
            let remaining = day.rows.filter { !ids.contains($0.id) }
            guard !remaining.isEmpty else { return nil }
            return DailyChallengeHistoryDay(localDate: day.localDate, date: day.date, rows: remaining)
        }
    }

    /// Parses a `yyyy-MM-dd` couple-local date into midnight UTC. Returns nil for a
    /// malformed string so the caller can fall back to a question's `startsAt`.
    /// Built from `DateComponents` rather than a shared `DateFormatter` so it stays
    /// concurrency-safe (a static `DateFormatter` is not `Sendable`).
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
}
