import Foundation

nonisolated extension LockScreenCalendarDate {
    /// This day moved to `year`. A 29 February falls on 28 February in a year that
    /// has no 29th, like `CoupleDateTimeline.nextBirthday` and `coupleDates.ts` on the server.
    func moved(toYear year: Int) -> Self {
        Self(year: year, month: month, day: min(day, Self.daysIn(month: month, year: year)))
    }

    /// The next time a date that repeats every year comes round, `today` included.
    /// A date still ahead is its own first occurrence.
    func nextYearlyOccurrence(onOrAfter today: Self) -> Self {
        let year = max(self.year, today.year)
        let thisYear = moved(toYear: year)
        return thisYear >= today ? thisYear : moved(toYear: year + 1)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func isLeap(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }
}
