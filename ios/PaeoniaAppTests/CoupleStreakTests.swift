import Foundation
import Testing
@testable import PaeoniaApp

/// Covers the predicted streak shown on the completion celebration. Answers send
/// local-first, so this math has to land on the same number the server will reach
/// once today's answer syncs.
struct CoupleStreakTests {
    @Test func consecutiveDayExtendsStoredCount() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 4,
            lastQualifiedDate: "2026-06-27",
            todayLocalDate: "2026-06-28"
        )

        #expect(count == 5)
    }

    @Test func alreadyCountedTodayKeepsStoredCount() {
        // The partner (or this user earlier) already kept the streak today.
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 5,
            lastQualifiedDate: "2026-06-28",
            todayLocalDate: "2026-06-28"
        )

        #expect(count == 5)
    }

    @Test func missedDayResetsToOne() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 9,
            lastQualifiedDate: "2026-06-25",
            todayLocalDate: "2026-06-28"
        )

        #expect(count == 1)
    }

    @Test func neverQualifiedStartsAtOne() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 0,
            lastQualifiedDate: nil,
            todayLocalDate: "2026-06-28"
        )

        #expect(count == 1)
    }

    @Test func extendsAcrossMonthBoundary() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 12,
            lastQualifiedDate: "2026-06-30",
            todayLocalDate: "2026-07-01"
        )

        #expect(count == 13)
    }

    @Test func missingTodayFallsBackWithoutShowingZero() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 7,
            lastQualifiedDate: "2026-06-27",
            todayLocalDate: nil
        )

        #expect(count == 7)
    }

    @Test func futureLastQualifiedDateDoesNotUndercount() {
        // Clock skew: stored date is ahead of "today". Don't reset to one.
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 8,
            lastQualifiedDate: "2026-06-29",
            todayLocalDate: "2026-06-28"
        )

        #expect(count == 8)
    }
}
