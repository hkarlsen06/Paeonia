import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenStatusTests {
    typealias Support = LockScreenTestSupport

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
}
