import Foundation
import Testing
@testable import PaeoniaApp

/// Covers which streak lengths are milestones, the streak sheet's badge row, and
/// when a phone celebrates one.
@MainActor
struct StreakMilestoneTests {
    @Test func milestonesAreTheFixedListThenEveryYear() {
        let milestones = (1...1_100).filter(StreakMilestones.isMilestone)

        #expect(milestones == [3, 7, 14, 30, 50, 100, 200, 365, 500, 730, 1_095])
    }

    @Test func nextAndPreviousMilestone() {
        #expect(StreakMilestones.next(after: 0) == 3)
        #expect(StreakMilestones.next(after: 7) == 14)
        #expect(StreakMilestones.next(after: 500) == 730)
        #expect(StreakMilestones.next(after: 731) == 1_095)
        #expect(StreakMilestones.previous(atOrBelow: 2) == 0)
        #expect(StreakMilestones.previous(atOrBelow: 12) == 7)
        #expect(StreakMilestones.previous(atOrBelow: 730) == 730)
    }

    @Test func progressRunsFromThePreviousMilestoneToTheNext() {
        #expect(StreakMilestones.progress(toward: 14, from: 7) == 0)
        #expect(StreakMilestones.progress(toward: 14, from: 12) == 5.0 / 7.0)
        #expect(StreakMilestones.progress(toward: 3, from: 0) == 0)
    }

    @Test func badgeRowKeepsTheNextMilestoneInView() {
        let early = StreakMilestones.badges(currentCount: 12, longestCount: 12)
        #expect(early.map(\.days) == [3, 7, 14, 30, 50, 100])
        #expect(early.filter(\.isEarned).map(\.days) == [3, 7])
        #expect(early.first(where: \.isNext)?.days == 14)

        let later = StreakMilestones.badges(currentCount: 40, longestCount: 40)
        #expect(later.map(\.days) == [7, 14, 30, 50, 100, 200])
        #expect(later.first(where: \.isNext)?.days == 50)
    }

    @Test func earnedBadgesFollowTheLongestStreakAfterABreak() {
        let badges = StreakMilestones.badges(currentCount: 1, longestCount: 31)

        #expect(badges.filter(\.isEarned).map(\.days) == [3, 7, 14, 30])
        #expect(badges.first(where: \.isNext)?.days == 3)
    }

    @Test func eachMilestoneIsClaimedOnce() {
        let first = StreakMilestoneTracker.claim(count: 7, shown: [3])
        #expect(first.milestone == 7)
        #expect(first.shown == [3, 7])

        let again = StreakMilestoneTracker.claim(count: 7, shown: first.shown)
        #expect(again.milestone == nil)
        #expect(StreakMilestoneTracker.claim(count: 8, shown: first.shown).milestone == nil)
    }

    @Test func aBreakLetsTheCoupleCelebrateAgain() {
        // The streak broke and restarted, so 3 and 7 are no longer behind them.
        let restarted = StreakMilestoneTracker.claim(count: 2, shown: [3, 7])
        #expect(restarted.shown.isEmpty)
        #expect(StreakMilestoneTracker.claim(count: 3, shown: restarted.shown).milestone == 3)
    }

    @Test func zeroNeverResetsShownMilestones() {
        // Zero shows before the streak loads, so it must not forget anything.
        let result = StreakMilestoneTracker.claim(count: 0, shown: [3, 7])

        #expect(result.shown == [3, 7])
        #expect(result.milestone == nil)
    }

    @Test func aRestoreSkipsTheMilestonesItBringsBack() {
        let shown = StreakMilestoneTracker.markRestored(upTo: 30, shown: [])

        #expect(shown == [3, 7, 14, 30])
        #expect(StreakMilestoneTracker.claim(count: 30, shown: shown).milestone == nil)
    }

    @Test func storeKeepsShownMilestonesPerUser() throws {
        let suiteName = "StreakMilestoneTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = StreakMilestoneStore(defaults: defaults)
        let user = UUID()
        let partner = UUID()

        #expect(store.claim(count: 7, userID: user) == 7)
        #expect(store.claim(count: 7, userID: user) == nil)
        // The partner's phone keeps its own record.
        #expect(store.claim(count: 7, userID: partner) == 7)
        store.markRestored(upTo: 14, userID: user)
        #expect(store.claim(count: 14, userID: user) == nil)
    }

    @Test func aStreakOnAMilestoneOpensTheMoment() {
        var streak = CoupleStreak.none
        streak.currentCount = 30

        #expect(streak.entryDestination == .milestone(30))
        streak.currentCount = 31
        #expect(streak.entryDestination == .detail)
    }

    @Test func pillShowsTheMilestoneDotOnlyForALiveStreak() {
        #expect(StreakPillState(count: 7, isRestorable: false, restorableCount: 0).isMilestone)
        #expect(!StreakPillState(count: 8, isRestorable: false, restorableCount: 0).isMilestone)
        #expect(!StreakPillState(count: 7, isRestorable: true, restorableCount: 30).isMilestone)
    }
}
