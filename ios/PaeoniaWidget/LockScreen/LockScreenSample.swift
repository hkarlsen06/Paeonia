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
            partner: Partner(displayName: "Alex", timeZoneID: "Asia/Tokyo"),
            startedOn: LockScreenCalendarDate(containing: now.addingTimeInterval(-412 * dayLength), in: calendar),
            upcomingCountdowns: [
                Countdown(
                    id: "sample",
                    title: "Trip",
                    targetDate: LockScreenCalendarDate(
                        containing: now.addingTimeInterval(12 * dayLength),
                        in: calendar
                    ),
                    createdAt: now.addingTimeInterval(-30 * dayLength)
                ),
            ],
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
}
#endif
