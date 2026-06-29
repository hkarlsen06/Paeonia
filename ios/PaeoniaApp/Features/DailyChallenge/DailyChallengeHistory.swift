import Foundation

/// One day's worth of answered questions in the history overview. Identified by the
/// couple's local date string so it stays stable across reloads, and carrying a
/// parsed `date` purely so the divider can format it in the reader's locale.
nonisolated struct DailyChallengeHistoryDay: Identifiable, Equatable, Sendable {
    /// The couple's local date as `yyyy-MM-dd`, e.g. "2026-06-27". Stable identity.
    let localDate: String
    /// Midnight of `localDate` in UTC, for locale-aware formatting in the divider.
    /// Formatting must pin the time zone to UTC so the displayed day never shifts.
    let date: Date
    let questions: [DailyChallengeQuestion]

    var id: String { localDate }
}

/// Pure grouping for the Questions history: turns the flat, chronological list of
/// answered questions into day groups, newest day first. Kept free of SwiftUI and
/// networking so the ordering rules are easy to unit test.
nonisolated enum DailyChallengeHistory {
    /// Groups answered questions by their couple-local date and returns the days
    /// newest-first. Within a day, questions are ordered by their most recent answer
    /// (latest first), then by slot, so the whole list reads most-recent-first and
    /// stays stable and deterministic.
    static func grouped(_ questions: [DailyChallengeQuestion]) -> [DailyChallengeHistoryDay] {
        Dictionary(grouping: questions, by: \.localDate)
            .map { localDate, dayQuestions in
                DailyChallengeHistoryDay(
                    localDate: localDate,
                    date: parseLocalDate(localDate) ?? dayQuestions.first?.startsAt ?? .distantPast,
                    questions: dayQuestions.sorted(by: withinDayOrder)
                )
            }
            .sorted { $0.localDate > $1.localDate }
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

    /// Most-recently-answered first within a day, then slot, then a stable id
    /// tiebreak. A question's sort time is the *latest* of its two answers — when the
    /// exchange was last completed — so an exchange the partner only just finished
    /// rises above one both people wrapped up earlier in the day.
    private static func withinDayOrder(
        _ lhs: DailyChallengeQuestion,
        _ rhs: DailyChallengeQuestion
    ) -> Bool {
        let lhsDate = latestAnswerDate(lhs)
        let rhsDate = latestAnswerDate(rhs)
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        if lhs.slotNumber != rhs.slotNumber { return lhs.slotNumber < rhs.slotNumber }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// The most recent answer time on a question — the later of the user's and the
    /// partner's answer — falling back to the day's start when neither is set.
    private static func latestAnswerDate(_ question: DailyChallengeQuestion) -> Date {
        [question.ownAnswer?.answeredAt, question.partnerAnswer?.answeredAt]
            .compactMap { $0 }
            .max() ?? question.startsAt
    }
}
