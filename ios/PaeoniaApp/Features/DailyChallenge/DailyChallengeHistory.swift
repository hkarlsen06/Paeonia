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
    /// Groups answered questions by their effective couple-local date — the day of
    /// their most recent answer — and returns the days newest-first. Within a day,
    /// questions are ordered by their most recent answer (latest first), then by slot,
    /// so the whole list reads most-recent-first and stays stable and deterministic.
    ///
    /// Grouping on `effectiveLocalDate` (not the instance's seed day) is what keeps a
    /// late-night exchange — partner answered before midnight, you answered after —
    /// under the day it was actually finished.
    static func grouped(_ questions: [DailyChallengeQuestion]) -> [DailyChallengeHistoryDay] {
        Dictionary(grouping: questions, by: \.effectiveLocalDate)
            .map { effectiveLocalDate, dayQuestions in
                DailyChallengeHistoryDay(
                    localDate: effectiveLocalDate,
                    date: parseLocalDate(effectiveLocalDate) ?? dayQuestions.first?.startsAt ?? .distantPast,
                    // Most-recently-answered first within a day — the same ordering the
                    // Questions tab's single list uses (`DailyChallengeQuestion`'s
                    // `latestAnswerDate` is the shared sort key).
                    questions: dayQuestions.sorted(by: DailyChallengeSnapshot.readOverviewOrder)
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
}
