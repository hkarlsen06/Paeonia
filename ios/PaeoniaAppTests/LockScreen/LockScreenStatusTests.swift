import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenStatusTests {
    typealias Support = LockScreenTestSupport

    @Test func streakRingLightsTheHalfForEachActivePartner() {
        #expect(LockScreenStreak.Ring(meActive: false, partnerActive: false) == .neither)
        #expect(LockScreenStreak.Ring(meActive: true, partnerActive: false) == .me)
        #expect(LockScreenStreak.Ring(meActive: false, partnerActive: true) == .partner)
        #expect(LockScreenStreak.Ring(meActive: true, partnerActive: true) == .both)
    }

    @Test func streakRingDrawsLeftHalfForMeRightHalfForPartnerAndOneCircleForBoth() {
        #expect(LockScreenStreak.Ring.neither.arcs.isEmpty)

        let me = LockScreenStreak.Ring.me.arcs
        #expect(me.count == 1)
        #expect(me[0].start >= 0.5 && me[0].end <= 1) // 6 o'clock up to 12 o'clock on the left

        let partner = LockScreenStreak.Ring.partner.arcs
        #expect(partner.count == 1)
        #expect(partner[0].start >= 0 && partner[0].end <= 0.5)

        // One closed circle, not two halves with seams.
        #expect(LockScreenStreak.Ring.both.arcs == [.init(start: 0, end: 1)])
    }

    @Test func streakFlagsResetWhenTheCoupleDayEnds() {
        let end = Date(timeIntervalSince1970: 1_792_274_400)
        let snapshot = Support.snapshot(
            coupleDayEndsAt: end,
            streak: .init(currentCount: 7, meActiveToday: true, partnerActiveToday: true)
        )

        let before = LockScreenStreak(snapshot, at: end.addingTimeInterval(-1))
        #expect(before?.ring == .both)
        #expect(before?.count == 7)

        let after = LockScreenStreak(snapshot, at: end)
        #expect(after?.ring == .neither)
        #expect(after?.count == 7)
    }

    @Test func streakIsMissingWithoutStreakData() {
        #expect(LockScreenStreak(Support.snapshot(), at: .now) == nil)
    }

    @Test(arguments: [
        (false, false, LockScreenQuestionState.waiting),
        (false, true, .partnerAnswered),
        (true, false, .waitingForPartner),
        (true, true, .bothAnswered),
    ])
    func questionStateMapsWhoAnswered(me: Bool, partner: Bool, expected: LockScreenQuestionState) {
        #expect(LockScreenQuestionState(meAnswered: me, partnerAnswered: partner) == expected)
    }

    @Test func questionAnswersResetWhenTheCoupleDayEnds() {
        let end = Date(timeIntervalSince1970: 1_792_274_400)
        let snapshot = Support.snapshot(
            coupleDayEndsAt: end,
            question: .init(meAnswered: true, partnerAnswered: true)
        )

        #expect(LockScreenQuestionState(snapshot, at: end.addingTimeInterval(-1)) == .bothAnswered)
        #expect(LockScreenQuestionState(snapshot, at: end) == .waiting)
        #expect(LockScreenQuestionState(Support.snapshot(), at: end) == nil)
    }

    @Test func questionWithoutACoupleDayNeverResets() {
        let snapshot = Support.snapshot(question: .init(meAnswered: true, partnerAnswered: false))
        #expect(LockScreenQuestionState(snapshot, at: .distantFuture) == .waitingForPartner)
    }

    @Test func yourMoveShowsABadgeOnlyForSeveralGamesAndBuildsTheGamePath() {
        let none = LockScreenYourMove(.init(myTurnCount: 0, firstMyTurnKind: "ludo"))
        #expect(!none.isMyTurn)
        #expect(none.badgeCount == nil)
        #expect(none.gamePath == nil)

        let one = LockScreenYourMove(.init(myTurnCount: 1, firstMyTurnKind: "draw_and_guess"))
        #expect(one.isMyTurn)
        #expect(one.badgeCount == nil)
        #expect(one.gamePath == "draw-and-guess")

        let three = LockScreenYourMove(.init(myTurnCount: 3, firstMyTurnKind: nil))
        #expect(three.badgeCount == 3)
        #expect(three.gamePath == nil)
    }

    @Test func gamePathMatchesTheAppsDeepLinkRoute() throws {
        let move = LockScreenYourMove(.init(myTurnCount: 1, firstMyTurnKind: GameKind.connectFour.rawValue))
        let path = try #require(move.gamePath)
        let url = try #require(URL(string: "paeonia://games/\(path)"))
        #expect(PaeoniaDeepLink(url) == .game(.connectFour))
    }

    @Test func lockScreenLinksMatchTheAppsRoutes() throws {
        #expect(PaeoniaDeepLink(try #require(URL(string: "paeonia://streak"))) == .streak)
        #expect(PaeoniaDeepLink(try #require(URL(string: "paeonia://daily/today"))) == .dailyToday(coupleDayID: nil))
    }

    @Test func widgetKindsAreUnique() {
        #expect(Set(LockScreenWidgetKind.all).count == 7)
    }

    @Test func onlyWritesThatChangeWidgetContentReloadTheLockScreen() {
        #expect(SyncPendingOperationKind.submitDailyAnswer.changesLockScreenWidgets)
        #expect(SyncPendingOperationKind.saveCountdown.changesLockScreenWidgets)
        #expect(SyncPendingOperationKind.boardGameMove.changesLockScreenWidgets)
        #expect(!SyncPendingOperationKind.sendThreadMessage.changesLockScreenWidgets)
        #expect(!SyncPendingOperationKind.updateLatestPartnerLocation.changesLockScreenWidgets)
    }
}
