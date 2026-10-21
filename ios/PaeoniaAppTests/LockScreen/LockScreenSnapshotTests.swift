import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenSnapshotTests {
    static let sampleJSON = """
    {
      "generated_at": "2026-10-17T09:15:30.123Z",
      "partner": { "name": "Elena Hansen", "uses_nickname": false, "time_zone_id": "Asia/Kolkata" },
      "started_on": "2025-08-31",
      "dates": {
        "countdowns": [
          {
            "id": "c1", "title": "Trip to Bergen", "target_date": "2026-10-29", "repeats_yearly": false,
            "created_at": "2026-09-01T10:00:00Z"
          },
          {
            "id": "c3", "title": "We met", "target_date": "2023-06-12", "repeats_yearly": true,
            "created_at": "2026-09-02T10:00:00.500Z"
          }
        ],
        "birthdays": [ { "is_mine": false, "birthday": "2001-07-01" } ]
      },
      "distance": { "meters": 7750000.5, "as_of": "2026-10-17T09:10:00.000Z" },
      "couple_day": {
        "local_date": "2026-10-17",
        "starts_at": "2026-10-16T22:00:00.000Z",
        "ends_at": "2026-10-17T22:00:00.000Z"
      },
      "streak": { "current_count": 12, "me_active_today": true, "partner_active_today": false },
      "daily_question": { "me_answered": false, "partner_answered": true },
      "games": { "my_turn_count": 2, "first_my_turn_kind": "draw_and_guess" }
    }
    """

    @Test func decodesContractWithFractionalAndWholeSecondTimestamps() throws {
        let snapshot = try LockScreenSnapshot.decode(Data(Self.sampleJSON.utf8))

        #expect(snapshot.partner?.name == "Elena Hansen")
        #expect(snapshot.partner?.shortName == "Elena")
        #expect(snapshot.partner?.timeZoneID == "Asia/Kolkata")
        #expect(snapshot.startedOn == LockScreenCalendarDate(year: 2_025, month: 8, day: 31))
        #expect(snapshot.dates.countdowns.count == 2)
        #expect(snapshot.dates.countdowns[0].targetDate == LockScreenCalendarDate(year: 2_026, month: 10, day: 29))
        #expect(snapshot.dates.countdowns[0].createdAt == Date(timeIntervalSince1970: 1_788_256_800))
        #expect(snapshot.dates.countdowns[1].createdAt.timeIntervalSince1970 == 1_788_343_200.5)
        #expect(snapshot.dates.countdowns[1].repeatsYearly)
        let birthday = LockScreenCalendarDate(year: 2_001, month: 7, day: 1)
        #expect(snapshot.dates.birthdays == [.init(isMine: false, birthday: birthday)])
        #expect(snapshot.distance?.meters == 7_750_000.5)
        #expect(snapshot.coupleDay?.endsAt.timeIntervalSince1970 == 1_792_274_400)
        #expect(snapshot.streak == .init(currentCount: 12, meActiveToday: true, partnerActiveToday: false))
        #expect(snapshot.dailyQuestion == .init(meAnswered: false, partnerAnswered: true))
        #expect(snapshot.games == .init(myTurnCount: 2, firstMyTurnKind: "draw_and_guess"))
        #expect(abs(snapshot.generatedAt.timeIntervalSince1970 - 1_792_228_530.123) < 0.001)
    }

    @Test func shortNameKeepsANicknameWholeAndCutsAnAccountNameToItsFirstWord() {
        let nickname = LockScreenSnapshot.Partner(name: "My love", usesNickname: true, timeZoneID: nil)
        let accountName = LockScreenSnapshot.Partner(name: "Elena Hansen", usesNickname: false, timeZoneID: nil)
        let unknown = LockScreenSnapshot.Partner(name: nil, usesNickname: false, timeZoneID: nil)

        #expect(nickname.shortName == "My love")
        #expect(accountName.shortName == "Elena")
        #expect(unknown.shortName == nil)
    }

    @Test func decodesNullsAndEmptyLists() throws {
        let json = """
        {
          "generated_at": "2026-10-17T09:15:30Z",
          "partner": null,
          "started_on": null,
          "dates": { "countdowns": [], "birthdays": [] },
          "distance": null,
          "couple_day": null,
          "streak": null,
          "daily_question": null,
          "games": { "my_turn_count": 0, "first_my_turn_kind": null }
        }
        """
        let snapshot = try LockScreenSnapshot.decode(Data(json.utf8))

        #expect(snapshot.partner == nil)
        #expect(snapshot.startedOn == nil)
        #expect(snapshot.dates.countdowns.isEmpty && snapshot.dates.birthdays.isEmpty)
        #expect(snapshot.distance == nil)
        #expect(snapshot.streak == nil)
        #expect(snapshot.dailyQuestion == nil)
        #expect(snapshot.games.firstMyTurnKind == nil)
    }

    @Test func rejectsABadCalendarDate() {
        let json = Self.sampleJSON.replacingOccurrences(of: "2025-08-31", with: "31/08/2025")
        #expect(throws: DecodingError.self) { try LockScreenSnapshot.decode(Data(json.utf8)) }
    }

    @Test func fullTimelinesReloadAfterAWeekAndEmptyOnesSoon() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let snapshot = try LockScreenSnapshot.decode(Data(Self.sampleJSON.utf8))
        let now = Date(timeIntervalSince1970: 1_792_228_530)
        let dates = LockScreenTimeline.entryDates(for: snapshot, now: now, calendar: calendar)

        let reload = LockScreenTimeline.reloadDate(for: snapshot, entryDates: dates, now: now)
        #expect(reload == dates.last)
        #expect(reload.timeIntervalSince(now) > 6 * 24 * 60 * 60)
        #expect(LockScreenTimeline.reloadDate(for: nil, entryDates: dates, now: now) == now.addingTimeInterval(15 * 60))
    }

    @Test func calendarDateParsingAndDayNumbers() {
        #expect(LockScreenCalendarDate("2026-02-29") != nil) // Shape only. Day counts treat it as March 1.
        #expect(LockScreenCalendarDate("2026-13-01") == nil)
        #expect(LockScreenCalendarDate("2026-1") == nil)
        #expect(LockScreenCalendarDate(year: 1_970, month: 1, day: 1).dayNumber == 0)
        #expect(LockScreenCalendarDate(year: 2_000, month: 3, day: 1).dayNumber == 11_017)
    }

    @Test func entryDatesAddMidnightAndTheEndOfTheCoupleDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let snapshot = try LockScreenSnapshot.decode(Data(Self.sampleJSON.utf8))
        let now = Date(timeIntervalSince1970: 1_792_228_530) // 05:15 on 17 October in New York
        let endOfCoupleDay = Date(timeIntervalSince1970: 1_792_274_400)
        let newYorkMidnight = Date(timeIntervalSince1970: 1_792_296_000) // 04:00 UTC on the 18th

        let dates = LockScreenTimeline.entryDates(for: snapshot, now: now, calendar: calendar)

        #expect(Array(dates.prefix(3)) == [now, endOfCoupleDay, newYorkMidnight])
        // Six more midnights follow, each a calendar day apart.
        #expect(dates.count == 9)
        #expect(dates.dropFirst(2).allSatisfy { calendar.component(.hour, from: $0) == 0 })
    }

    @Test func entryDatesSkipACoupleDayThatAlreadyEnded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let snapshot = try LockScreenSnapshot.decode(Data(Self.sampleJSON.utf8))
        let now = Date(timeIntervalSince1970: 1_792_274_400 + 10)

        let dates = LockScreenTimeline.entryDates(for: snapshot, now: now, calendar: calendar)

        #expect(dates.count == 1 + LockScreenTimeline.daysAhead)
        #expect(dates.first == now)
    }
}
