import Foundation

nonisolated extension Visit {
    /// The first day, at the start of the day on this phone's calendar.
    func startDay(calendar: Calendar = .current) -> Date? {
        LockScreenCalendarDate(startDate)?.startOfDay(in: calendar)
    }

    func endDay(calendar: Calendar = .current) -> Date? {
        LockScreenCalendarDate(endDate)?.startOfDay(in: calendar)
    }

    /// The first and last day in the phone's language, such as Fri 20 to Mon 23 Nov, or one
    /// day when the visit is a single day.
    func dateRangeText(calendar: Calendar = .current) -> String {
        guard let start = startDay(calendar: calendar), let end = endDay(calendar: calendar) else { return "" }
        guard end > start else {
            return start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        var style = Date.IntervalFormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return (start..<end).formatted(style)
    }

    /// The dates timeline row: "Together in Bergen", or "Together again" without a place.
    var timelineTitle: String {
        guard let place else { return String(localized: .visitTimelineTitle) }
        return String(localized: .visitTimelineTitlePlace(place.shortName))
    }
}

nonisolated extension Visit.Phase {
    /// "12 days to go", "Tomorrow" or "You're together". Nil once the visit is over, since
    /// the card and the visit screen only show a visit that is not.
    var headline: String? {
        switch self {
        case .upcoming(days: 1):
            String(localized: .visitCountdownTomorrow)
        case let .upcoming(days):
            String(localized: .visitCountdownDays(days.formatted()))
        case .ongoing:
            String(localized: .visitCountdownOngoing)
        case .ended:
            nil
        }
    }
}
