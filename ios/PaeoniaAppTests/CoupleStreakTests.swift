import Foundation
import Testing
@testable import PaeoniaApp

/// Covers the predicted streak shown on the completion celebration. Answers send
/// local-first, so this math has to land on the same number the server will reach
/// once today's answer syncs.
struct CoupleStreakTests {
    @Test func consecutiveDayExtendsStoredCountWhenPartnerAlreadyContributed() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 4,
            lastQualifiedDate: "2026-06-27",
            todayLocalDate: "2026-06-28",
            partnerContributedToday: true
        )

        #expect(count == 5)
    }

    @Test func currentUsersCompletionDoesNotAdvanceStreakAlone() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 4,
            lastQualifiedDate: "2026-06-27",
            todayLocalDate: "2026-06-28",
            partnerContributedToday: false
        )

        #expect(count == 4)
    }

    @Test func alreadyCountedTodayKeepsStoredCount() {
        // The server has already recorded the mutually qualified day.
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 5,
            lastQualifiedDate: "2026-06-28",
            todayLocalDate: "2026-06-28",
            partnerContributedToday: false
        )

        #expect(count == 5)
    }

    @Test func expiredServerCountStartsAgainAtOne() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 0,
            lastQualifiedDate: "2026-06-25",
            todayLocalDate: "2026-06-28",
            partnerContributedToday: true
        )

        #expect(count == 1)
    }

    @Test func neverQualifiedStartsAtOneWhenBothHaveContributed() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 0,
            lastQualifiedDate: nil,
            todayLocalDate: "2026-06-28",
            partnerContributedToday: true
        )

        #expect(count == 1)
    }

    @Test func extendsAcrossMonthBoundary() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 12,
            lastQualifiedDate: "2026-06-30",
            todayLocalDate: "2026-07-01",
            partnerContributedToday: true
        )

        #expect(count == 13)
    }

    @Test func missingTodayFallsBackWithoutShowingZero() {
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 7,
            lastQualifiedDate: "2026-06-27",
            todayLocalDate: nil,
            partnerContributedToday: true
        )

        #expect(count == 7)
    }

    @Test func crossingTheDateLineStillExtendsALiveStreak() {
        // Travel can make the current couple date sort before the last recorded
        // date. The server's live count, not date ordering, owns expiration.
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 8,
            lastQualifiedDate: "2026-06-29",
            todayLocalDate: "2026-06-28",
            partnerContributedToday: true
        )

        #expect(count == 9)
    }

    @Test func legacyCachedStreakDefaultsParticipationToIncomplete() throws {
        let data = Data(
            #"{"current_count":4,"longest_count":8,"last_qualified_date":"2026-06-27","restore_available":false,"restorable_count":0,"restore_deadline":null}"#.utf8
        )

        let row = try JSONDecoder().decode(CoupleStreakRow.self, from: data)

        #expect(!row.currentUserContributedToday)
        #expect(!row.partnerContributedToday)
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

    @Test func brokenStreakEntryGoesStraightToRestoreOffer() {
        let streak = CoupleStreak(
            currentCount: 0,
            longestCount: 30,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: true,
            restorableCount: 30,
            restoreDeadline: .now.addingTimeInterval(3_600)
        )

        #expect(streak.entryDestination == .restore)
    }

    @Test func healthyOrExpiredStreakEntryOpensReadOnlyDetail() {
        let expired = CoupleStreak(
            currentCount: 0,
            longestCount: 30,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: true,
            restorableCount: 30,
            restoreDeadline: .now.addingTimeInterval(-1)
        )

        #expect(CoupleStreak.none.entryDestination == .detail)
        #expect(expired.entryDestination == .detail)
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

    // MARK: - Toolbar restore state

    @Test func pillOfARestorableStreakAdvertisesTheLostCount() {
        let deadline = Date.now.addingTimeInterval(3_600)
        let state = StreakPillState(Self.streak(restorableCount: 30, deadline: deadline))

        #expect(state.isRestorable)
        #expect(state.displayCount == 30)
        #expect(state.usesMutedFlame)
        #expect(state.restoreDeadline == deadline)
    }

    @Test func pillOfAHealthyStreakShowsTheLiveCount() {
        let state = StreakPillState(Self.streak(currentCount: 5, restorableCount: 0, deadline: nil))

        #expect(!state.isRestorable)
        #expect(state.displayCount == 5)
        #expect(!state.usesMutedFlame)
        #expect(state.restoreDeadline == nil)
    }

    @Test func pillOfAnExpiredOfferShowsTheLiveCount() {
        let state = StreakPillState(
            Self.streak(restorableCount: 30, deadline: Date.now.addingTimeInterval(-60))
        )

        #expect(!state.isRestorable)
        #expect(state.displayCount == 1)
    }

    @Test func pillStopsOfferingARestoreExactlyAtTheDeadline() {
        let deadline = Date.now.addingTimeInterval(3_600)
        let state = StreakPillState(Self.streak(restorableCount: 30, deadline: deadline))

        #expect(state.resolved(at: deadline.addingTimeInterval(-1)).isRestorable)
        #expect(!state.resolved(at: deadline).isRestorable)
        #expect(!state.resolved(at: deadline.addingTimeInterval(1)).isRestorable)
        // Back to the live count, not the lost one.
        #expect(state.resolved(at: deadline).displayCount == 1)
    }

    @Test func pillWithoutADeadlineNeverLapses() {
        let state = StreakPillState(count: 1, isRestorable: true, restorableCount: 30)

        #expect(state.resolved(at: .distantFuture).isRestorable)
    }

    private static func streak(
        currentCount: Int = 1,
        restorableCount: Int,
        deadline: Date?
    ) -> CoupleStreak {
        CoupleStreak(
            currentCount: currentCount,
            longestCount: 30,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: restorableCount > 0,
            restorableCount: restorableCount,
            restoreDeadline: deadline
        )
    }
}
