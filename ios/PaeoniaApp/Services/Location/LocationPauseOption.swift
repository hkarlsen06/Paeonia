import Foundation

/// The lengths of pause the app offers. Each one turns into a fixed end time when
/// it is chosen. The server stores that time, so a phone that crosses time zones
/// afterwards does not move it.
nonisolated enum LocationPauseOption: CaseIterable, Identifiable, Sendable {
    case oneHour
    case fourHours
    case untilMorning

    var id: Self { self }

    /// "Until morning" ends at 08:00 on the clock of the time zone chosen at the tap.
    static let morningHour = 8

    /// An "until morning" pause shorter than this runs to the following morning
    /// instead. Someone who taps it at 07:40 means tomorrow.
    static let shortestMorningPause: TimeInterval = 60 * 60

    func end(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            now.addingTimeInterval(60 * 60)
        case .fourHours:
            now.addingTimeInterval(4 * 60 * 60)
        case .untilMorning:
            Self.morning(after: now, calendar: calendar)
        }
    }

    private static func morning(after now: Date, calendar: Calendar) -> Date {
        let morning = DateComponents(hour: morningHour, minute: 0, second: 0)
        // A day in a time zone can skip 08:00 on a daylight saving change, so ask the
        // calendar for the next real 08:00 and not "tomorrow plus a day".
        guard let next = calendar.nextDate(
            after: now,
            matching: morning,
            matchingPolicy: .nextTime
        ) else {
            return now.addingTimeInterval(12 * 60 * 60)
        }
        guard next.timeIntervalSince(now) < shortestMorningPause else {
            return next
        }
        return calendar.nextDate(after: next, matching: morning, matchingPolicy: .nextTime)
            ?? next.addingTimeInterval(24 * 60 * 60)
    }
}

nonisolated enum LocationPauseEndText {
    /// "22:00" when the pause ends today, "Thursday 08:00" when it ends on another day,
    /// in the phone's language and clock style.
    static func text(
        for end: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var style: Date.FormatStyle = .dateTime.hour().minute()
        if !calendar.isDate(end, inSameDayAs: now) {
            style = style.weekday(.wide)
        }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return end.formatted(style)
    }
}
