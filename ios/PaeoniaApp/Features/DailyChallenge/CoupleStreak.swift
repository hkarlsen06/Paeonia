import Foundation

/// The couple's shared daily-challenge streak, as stored on the server.
///
/// The backend owns this value: a trigger updates `streak_states` whenever a
/// daily challenge is completed (consecutive-day counting, per-couple timezone
/// day boundaries, shared between partners). The app only reads it.
nonisolated struct CoupleStreak: Equatable, Sendable {
    var currentCount: Int
    var longestCount: Int
    /// The couple's local date (`yyyy-MM-dd`) the streak last counted, or `nil`
    /// if it has never counted. Used to predict today's increment before the
    /// just-sent answer has synced.
    var lastQualifiedDate: String?
    var restoreAvailable: Bool

    static let none = CoupleStreak(
        currentCount: 0,
        longestCount: 0,
        lastQualifiedDate: nil,
        restoreAvailable: false
    )
}

/// Pure logic for the number shown on the completion celebration.
///
/// Answers are sent local-first, so when the celebration appears the server
/// streak may not yet reflect today's completion. Rather than wait on the
/// network (which would stall the moment, and never resolve offline), we predict
/// the post-completion count from the stored streak and the couple's local date
/// — the same rule the server applies when the answer lands.
enum StreakCelebration {
    /// The streak to show now that the user has finished today's challenge.
    ///
    /// - `serverCurrentCount`: the stored `current_count` (through `lastQualifiedDate`).
    /// - `lastQualifiedDate` / `todayLocalDate`: couple-local dates as `yyyy-MM-dd`.
    static func celebratedCount(
        serverCurrentCount: Int,
        lastQualifiedDate: String?,
        todayLocalDate: String?
    ) -> Int {
        guard let todayLocalDate, let today = day(from: todayLocalDate) else {
            // No local date to reason about — show the stored count, but never 0
            // on a screen the user only reaches by completing today.
            return max(serverCurrentCount, 1)
        }

        guard let lastQualifiedDate, let last = day(from: lastQualifiedDate) else {
            // Never counted before: today is day one.
            return 1
        }

        let dayGap = Calendar.streakUTC.dateComponents([.day], from: last, to: today).day ?? 0
        switch dayGap {
        case 0:
            // Already counted today (the user earlier, or their partner).
            return serverCurrentCount
        case 1:
            // Yesterday was the last day — today extends the streak.
            return serverCurrentCount + 1
        default:
            // A missed day resets to one; a negative gap (clock skew) is treated
            // as "don't undercount what's stored".
            return dayGap < 0 ? max(serverCurrentCount, 1) : 1
        }
    }

    /// Parses a `yyyy-MM-dd` couple-local date into a UTC calendar day so day
    /// math is exact and free of the device's own timezone.
    private static func day(from localDate: String) -> Date? {
        let parts = localDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.streakUTC.date(from: components)
    }
}

private extension Calendar {
    static let streakUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
