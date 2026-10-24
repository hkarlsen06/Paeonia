import Foundation
import Testing
@testable import PaeoniaApp

/// Covers the predicted streak shown on the completion celebration. Answers send
/// local-first, so this math has to land on the same number the server will reach
/// once today's answer syncs.
@MainActor
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

    @Test func showingUpOnTheSaveDayBringsTheBrokenStreakBackWithToday() {
        // The server count is 0 after the break. The partner already showed up today,
        // so this answer brings the 12 days back and today counts on top.
        let count = StreakCelebration.celebratedCount(
            serverCurrentCount: 0,
            lastQualifiedDate: "2026-06-26",
            todayLocalDate: "2026-06-28",
            partnerContributedToday: true,
            savableCount: 12
        )
        let alone = StreakCelebration.celebratedCount(
            serverCurrentCount: 0,
            lastQualifiedDate: "2026-06-26",
            todayLocalDate: "2026-06-28",
            partnerContributedToday: false,
            savableCount: 12
        )

        #expect(count == 13)
        #expect(alone == 0)
    }

    @Test func decodesStreakFreezeFields() throws {
        let data = Data(
            """
            {"current_count":6,"longest_count":8,"last_qualified_date":"2026-10-10",
            "restore_available":false,"restorable_count":0,"restore_deadline":null,
            "current_user_contributed_today":true,"partner_contributed_today":false,
            "freeze_available":false,"freeze_ready_at":"2026-11-10T22:00:00.000Z","freeze_saved_streak":true,
            "next_activity_deadline_at":"2026-11-10T22:00:00.000Z"}
            """.utf8
        )

        let streak = try PaeoniaConvexClient.decoder.decode(CoupleStreakRow.self, from: data).streak

        #expect(!streak.freezeAvailable)
        #expect(streak.freezeReadyAt == Date(timeIntervalSince1970: 1_794_348_000))
        #expect(streak.freezeSavedStreak)
        #expect(streak.endsAt == Date(timeIntervalSince1970: 1_794_348_000))
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

    @Test func theFreeSaveDayComesBeforeThePaidRestore() {
        var streak = Self.streak(currentCount: 0, restorableCount: 12, deadline: .now.addingTimeInterval(50 * 3_600))
        streak.saveDeadline = .now.addingTimeInterval(2 * 3_600)

        #expect(streak.isSavable)
        #expect(!streak.isRestorable)
        // The save day opens the informative sheet, never the purchase.
        #expect(streak.entryDestination == .detail)

        streak.saveDeadline = .now.addingTimeInterval(-60)
        #expect(!streak.isSavable)
        #expect(streak.isRestorable)
        #expect(streak.entryDestination == .restore)
    }

    @Test func decodesTheSaveDayAndTheLastSave() throws {
        let data = Data(
            """
            {"current_count":0,"longest_count":12,"last_qualified_date":"2026-10-10",
            "save_available":true,"restore_available":false,"restorable_count":12,
            "save_deadline":"2026-11-10T22:00:00.000Z","restore_deadline":"2026-11-12T22:00:00.000Z",
            "saved_on":"2026-09-01","current_user_contributed_today":false,"partner_contributed_today":false,
            "freeze_available":false,"freeze_ready_at":null,"freeze_saved_streak":false,
            "next_activity_deadline_at":null}
            """.utf8
        )

        let streak = try PaeoniaConvexClient.decoder.decode(CoupleStreakRow.self, from: data).streak

        #expect(streak.saveDeadline == Date(timeIntervalSince1970: 1_794_348_000))
        #expect(streak.savedOn == "2026-09-01")
        // The save is not the streak's newest day, so it is not celebrated again.
        #expect(streak.freshSaveDay == nil)
    }

    // MARK: - Toolbar restore state

    @Test func pillTurnsFromTheSaveDayToTheRestoreOffer() {
        let saveDeadline = Date.now.addingTimeInterval(3_600)
        let restoreDeadline = saveDeadline.addingTimeInterval(48 * 3_600)
        var streak = Self.streak(currentCount: 0, restorableCount: 12, deadline: restoreDeadline)
        streak.saveDeadline = saveDeadline
        let state = StreakPillState(streak)

        let saveDay = state.resolved(at: saveDeadline.addingTimeInterval(-1))
        #expect(saveDay.isSavable)
        #expect(!saveDay.isRestorable)
        #expect(saveDay.displayCount == 12)
        #expect(saveDay.usesMutedFlame)
        #expect(state.changeDates == [saveDeadline, restoreDeadline])

        let restoreDays = state.resolved(at: saveDeadline)
        #expect(!restoreDays.isSavable)
        #expect(restoreDays.isRestorable)
        #expect(restoreDays.displayCount == 12)

        let gone = state.resolved(at: restoreDeadline)
        #expect(!gone.isPaused)
        #expect(gone.displayCount == 0)
    }

    @Test func pillOfARestorableStreakAdvertisesTheLostCount() {
        let deadline = Date.now.addingTimeInterval(3_600)
        let state = StreakPillState(Self.streak(restorableCount: 30, deadline: deadline))

        #expect(state.isRestorable)
        #expect(state.displayCount == 30)
        #expect(state.usesMutedFlame)
        #expect(state.restoreDeadline == deadline)
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

    // MARK: - Toolbar ends-soon state

    @Test func pillShowsTheHourglassOnlyCloseToTheEnd() {
        let endsAt = Date.now.addingTimeInterval(24 * 3_600)
        let atRiskFrom = endsAt.addingTimeInterval(-StreakPillState.atRiskLeadTime)
        let state = StreakPillState(count: 12, isRestorable: false, restorableCount: 0, endsAt: endsAt)

        #expect(!state.resolved(at: atRiskFrom.addingTimeInterval(-1)).isAtRisk)
        #expect(state.resolved(at: atRiskFrom).isAtRisk)
        #expect(state.changeDates == [atRiskFrom])
    }

    @Test func pillWithoutALiveStreakNeverShowsTheHourglass() {
        let endsAt = Date.now.addingTimeInterval(60)
        let zero = StreakPillState(count: 0, isRestorable: false, restorableCount: 0, endsAt: endsAt)
        let paused = StreakPillState(count: 1, isRestorable: true, restorableCount: 30, endsAt: endsAt)

        #expect(!zero.resolved(at: endsAt).isAtRisk)
        #expect(!paused.resolved(at: endsAt).isAtRisk)
        #expect(zero.changeDates.isEmpty)
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

/// Covers which freeze line the streak sheet shows.
@MainActor
struct StreakFreezeNoteTests {
    private func freezeStreak(
        currentCount: Int = 6,
        freezeAvailable: Bool = false,
        freezeReadyAt: Date? = nil,
        freezeSavedStreak: Bool = false
    ) -> CoupleStreak {
        CoupleStreak(
            currentCount: currentCount,
            longestCount: 8,
            lastQualifiedDate: "2026-10-10",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil,
            freezeAvailable: freezeAvailable,
            freezeReadyAt: freezeReadyAt,
            freezeSavedStreak: freezeSavedStreak
        )
    }

    @Test func freezeNoteSaysWhenAFreezeSavedTheStreak() {
        let readyAt = Date.now.addingTimeInterval(30 * 86_400)
        let streak = freezeStreak(freezeReadyAt: readyAt, freezeSavedStreak: true)

        #expect(streak.freezeNote() == .savedStreak)
    }

    @Test func freezeNoteTreatsAPassedReadyDateAsNothingToSay() {
        // The server says whether the freeze protects this streak. A stale date alone is not a promise.
        let streak = freezeStreak(freezeReadyAt: .now.addingTimeInterval(-60))

        #expect(streak.freezeNote() == nil)
    }

    @Test func freezeNoteIsHiddenWithoutALiveStreak() {
        #expect(freezeStreak(currentCount: 0, freezeAvailable: true).freezeNote() == nil)
        #expect(freezeStreak(currentCount: 2).freezeNote() == nil)
    }
}
