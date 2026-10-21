import Foundation
@testable import PaeoniaApp

enum LockScreenTestSupport {
    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    /// A moment given as wall-clock time in `calendar`'s time zone.
    static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
        in calendar: Calendar
    ) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: parts) ?? .distantPast
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> LockScreenCalendarDate {
        LockScreenCalendarDate(year: year, month: month, day: day)
    }

    static func snapshot(
        coupleDayEndsAt: Date? = nil,
        streak: LockScreenSnapshot.Streak? = nil,
        question: LockScreenSnapshot.DailyQuestion? = nil
    ) -> LockScreenSnapshot {
        LockScreenSnapshot(
            generatedAt: .distantPast,
            partner: nil,
            startedOn: nil,
            dates: .init(countdowns: [], birthdays: []),
            distance: nil,
            coupleDay: coupleDayEndsAt.map {
                LockScreenSnapshot.CoupleDay(localDate: "", startsAt: $0.addingTimeInterval(-86_400), endsAt: $0)
            },
            streak: streak,
            dailyQuestion: question,
            games: .init(myTurnCount: 0, firstMyTurnKind: nil)
        )
    }
}
