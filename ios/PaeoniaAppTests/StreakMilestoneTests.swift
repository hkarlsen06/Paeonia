import Foundation
import Testing
@testable import PaeoniaApp

/// Covers when a phone celebrates a streak milestone and how it remembers that.
@MainActor
struct StreakMilestoneTests {
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

    @Test func aFreeSaveIsCelebratedOnceAndSkipsTheMilestonesItBringsBack() throws {
        let suiteName = "StreakMilestoneTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = StreakMilestoneStore(defaults: defaults)
        let user = UUID()

        #expect(store.claimSave(on: "2026-10-12", count: 7, userID: user))
        #expect(!store.claimSave(on: "2026-10-12", count: 7, userID: user))
        // The save has its own moment, so reaching 7 with it is not a second one.
        #expect(store.claim(count: 7, userID: user) == nil)
        // A later save is a new moment.
        #expect(store.claimSave(on: "2026-11-02", count: 4, userID: user))
    }
}
