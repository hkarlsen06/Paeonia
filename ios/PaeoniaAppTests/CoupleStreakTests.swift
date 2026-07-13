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

    @Test func expiredServerCountStartsAgainAtOne() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 0,
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

    @Test func crossingTheDateLineStillExtendsALiveStreak() {
        // Travel can make the current couple date sort before the last recorded
        // date. The server's live count, not date ordering, owns expiration.
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 8,
            lastQualifiedDate: "2026-06-29",
            todayLocalDate: "2026-06-28"
        )

        #expect(count == 9)
    }

    // MARK: - Restore eligibility

    @Test func restorableWhenCountPositiveAndDeadlineInFuture() {
        let streak = CoupleStreak(
            currentCount: 1,
            longestCount: 30,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: true,
            restorableCount: 30,
            restoreDeadline: .now.addingTimeInterval(3_600)
        )

        #expect(streak.isRestorable)
    }

    @Test func notRestorableOnceDeadlineHasPassed() {
        let streak = CoupleStreak(
            currentCount: 1,
            longestCount: 30,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: true,
            restorableCount: 30,
            restoreDeadline: .now.addingTimeInterval(-3_600)
        )

        #expect(!streak.isRestorable)
    }

    @Test func notRestorableWithoutARestorableCount() {
        let streak = CoupleStreak(
            currentCount: 5,
            longestCount: 5,
            lastQualifiedDate: "2026-06-28",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: .now.addingTimeInterval(3_600)
        )

        #expect(!streak.isRestorable)
    }

    @Test func noneIsNotRestorable() {
        #expect(!CoupleStreak.none.isRestorable)
    }

    // MARK: - Toolbar presentation

    @Test func zeroStreakRemainsVisibleWithAMutedFlame() {
        let state = StreakPillState(
            count: 0,
            isRestorable: false,
            restorableCount: 0
        )

        #expect(state.isVisible)
        #expect(state.displayCount == 0)
        #expect(state.usesMutedFlame)
    }

    @Test func healthyStreakUsesTheLiveFlame() {
        let state = StreakPillState(
            count: 1,
            isRestorable: false,
            restorableCount: 0
        )

        #expect(state.isVisible)
        #expect(!state.usesMutedFlame)
    }

    @Test func explicitlyUnavailableStreakStateRemainsHidden() {
        #expect(!StreakPillState.hidden.isVisible)
    }
}
