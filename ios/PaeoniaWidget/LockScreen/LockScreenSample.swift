#if WIDGET_EXTENSION
import Foundation

extension LockScreenSnapshot {
    /// Made-up values for the widget picker and Xcode previews. A widget on the
    /// Lock Screen never shows these. It shows the neutral state until real data arrives.
    static func sample(now: Date, calendar: Calendar = .current) -> LockScreenSnapshot {
        let dayLength: TimeInterval = 24 * 60 * 60
        let startOfToday = calendar.startOfDay(for: now)
        return LockScreenSnapshot(
            generatedAt: now,
            partner: Partner(name: "Alex", usesNickname: false, timeZoneID: "Asia/Tokyo"),
            startedOn: LockScreenCalendarDate(containing: now.addingTimeInterval(-412 * dayLength), in: calendar),
            dates: sampleDates(now: now, calendar: calendar),
            distance: Distance(meters: 7_750_000, asOf: now),
            coupleDay: CoupleDay(
                localDate: "",
                startsAt: startOfToday,
                endsAt: startOfToday.addingTimeInterval(dayLength)
            ),
            streak: Streak(currentCount: 12, meActiveToday: true, partnerActiveToday: true),
            dailyQuestion: DailyQuestion(meAnswered: false, partnerAnswered: true),
            games: Games(myTurnCount: 1, firstMyTurnKind: "ludo")
        )
    }

    /// A trip, a yearly anniversary and a birthday, for the countdown widget.
    private static func sampleDates(now: Date, calendar: Calendar) -> Dates {
        let dayLength: TimeInterval = 24 * 60 * 60
        func day(_ offset: Double) -> LockScreenCalendarDate {
            LockScreenCalendarDate(containing: now.addingTimeInterval(offset * dayLength), in: calendar)
        }
        let created = now.addingTimeInterval(-30 * dayLength)
        return Dates(
            countdowns: [
                DatedCountdown(
                    id: "sample", title: "Trip", targetDate: day(12), repeatsYearly: false, createdAt: created
                ),
                DatedCountdown(
                    id: "anniversary", title: "First date", targetDate: day(-300), repeatsYearly: true,
                    createdAt: created
                ),
            ],
            birthdays: [Birthday(isMine: false, birthday: day(40 - 9_000))]
        )
    }
}
#endif
