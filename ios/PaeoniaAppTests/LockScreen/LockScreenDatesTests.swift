import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenDatesTests {
    typealias Support = LockScreenTestSupport

    private func countdown(
        _ id: String, _ target: LockScreenCalendarDate, yearly: Bool = false, createdAt: Date = .distantPast
    ) -> LockScreenSnapshot.DatedCountdown {
        .init(id: id, title: id, targetDate: target, repeatsYearly: yearly, createdAt: createdAt)
    }

    @Test func yearlyDatesComeRoundOnTheSameDayEachYear() {
        let met = Support.day(2_023, 6, 12)
        // Later this year, today, and already passed this year.
        #expect(met.nextYearlyOccurrence(onOrAfter: Support.day(2_026, 5, 1)) == Support.day(2_026, 6, 12))
        #expect(met.nextYearlyOccurrence(onOrAfter: Support.day(2_026, 6, 12)) == Support.day(2_026, 6, 12))
        #expect(met.nextYearlyOccurrence(onOrAfter: Support.day(2_026, 6, 13)) == Support.day(2_027, 6, 12))
        // A date still ahead is its own first occurrence.
        #expect(met.nextYearlyOccurrence(onOrAfter: Support.day(2_020, 1, 1)) == met)
    }

    @Test func aLeapDayFallsOnTheTwentyEighthInOtherYears() {
        let leap = Support.day(2_000, 2, 29)
        #expect(leap.nextYearlyOccurrence(onOrAfter: Support.day(2_026, 1, 1)) == Support.day(2_026, 2, 28))
        #expect(leap.nextYearlyOccurrence(onOrAfter: Support.day(2_027, 3, 1)) == Support.day(2_028, 2, 29))
        // 1900 and 2100 are not leap years.
        #expect(Support.day(2_000, 2, 29).moved(toYear: 2_100) == Support.day(2_100, 2, 28))
    }

    @Test func listsDatesSoonestFirstWithYearlyOnesMovedToTheirNextDay() {
        let today = Support.day(2_026, 10, 17)
        let dates = LockScreenSnapshot.Dates(
            countdowns: [
                countdown("far", Support.day(2_027, 1, 1)),
                countdown("anniversary", Support.day(2_023, 10, 25), yearly: true),
                countdown("yesterday", Support.day(2_026, 10, 16)),
                countdown("today", today),
            ],
            birthdays: [.init(isMine: false, birthday: Support.day(2_001, 10, 25))]
        )

        let items = LockScreenDates.items(in: dates, today: today)

        // Yesterday's one-off countdown is gone. The birthday comes before the
        // countdown that falls on the same day.
        #expect(items.map(\.id) == ["countdown:today", "birthday:partner", "countdown:anniversary", "countdown:far"])
        #expect(items.map(\.daysRemaining) == [0, 8, 8, 76])
        #expect(items[0].remaining == .today)
    }

    @Test func aYearlyCountdownThatPassedYesterdayShowsNextYear() {
        let dates = LockScreenSnapshot.Dates(
            countdowns: [countdown("met", Support.day(2_023, 10, 16), yearly: true)],
            birthdays: []
        )
        let items = LockScreenDates.items(in: dates, today: Support.day(2_026, 10, 17))
        #expect(items.first?.date == Support.day(2_027, 10, 16))
        #expect(items.first?.daysRemaining == 364)
    }

    @Test func aChosenDateIsShownAndAnythingElseFallsBackToTheSoonest() {
        let today = Support.day(2_026, 10, 17)
        let dates = LockScreenSnapshot.Dates(
            countdowns: [countdown("soon", Support.day(2_026, 10, 20)), countdown("later", Support.day(2_026, 12, 1))],
            birthdays: []
        )
        let items = LockScreenDates.items(in: dates, today: today)

        #expect(LockScreenDates.selected(id: "countdown:later", in: items)?.id == "countdown:later")
        #expect(LockScreenDates.selected(id: LockScreenDates.nextID, in: items)?.id == "countdown:soon")
        #expect(LockScreenDates.selected(id: nil, in: items)?.id == "countdown:soon")
        // The chosen countdown was deleted.
        #expect(LockScreenDates.selected(id: "countdown:gone", in: items)?.id == "countdown:soon")
        #expect(LockScreenDates.selected(id: nil, in: []) == nil)
    }

    @Test func comingUpSkipsTheShownDateAndKeepsOrder() {
        let today = Support.day(2_026, 10, 17)
        let dates = LockScreenSnapshot.Dates(
            countdowns: (1...4).map { countdown("c\($0)", Support.day(2_026, 10, 17 + $0)) },
            birthdays: []
        )
        let items = LockScreenDates.items(in: dates, today: today)
        let shown = items[1]
        let following = LockScreenDates.comingUp(after: shown, in: items, limit: 2)
        #expect(following.map(\.id) == ["countdown:c1", "countdown:c3"])
    }

    @Test func progressStartsAtCreationInTheFirstYearAndAtTheOccurrenceBeforeAfterwards() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let dates = LockScreenSnapshot.Dates(
            countdowns: [
                countdown("trip", Support.day(2_026, 12, 1), createdAt: created),
                countdown("first", Support.day(2_026, 11, 1), yearly: true, createdAt: created),
                countdown("again", Support.day(2_023, 10, 25), yearly: true, createdAt: created),
            ],
            birthdays: [.init(isMine: true, birthday: Support.day(2_000, 10, 20))]
        )

        let items = LockScreenDates.items(in: dates, today: Support.day(2_026, 10, 17))
        let starts = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.progressStart) })

        #expect(starts["countdown:trip"] == .created(created))
        #expect(starts["countdown:first"] == .created(created))
        #expect(starts["countdown:again"] == .day(Support.day(2_025, 10, 25)))
        #expect(starts["birthday:me"] == .some(nil))
    }
}
