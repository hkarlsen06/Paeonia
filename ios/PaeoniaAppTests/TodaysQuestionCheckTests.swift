import Foundation
import Testing
@testable import PaeoniaApp

struct TodaysQuestionCheckTests {
    private let since = ContinuousClock.now
    private let today = "2026-11-15"

    private func check(
        visit: TodaysQuestionVisit? = nil,
        isAppReady: Bool = true,
        isIntroComplete: Bool = true,
        isHomeInFront: Bool = true,
        partnerHasAnswered: Bool = false,
        isCardLoaded: Bool = true
    ) -> TodaysQuestionCheck {
        TodaysQuestionCheck(
            visit: visit ?? .ready(since: since),
            isAppReady: isAppReady,
            isIntroComplete: isIntroComplete,
            isHomeInFront: isHomeInFront,
            openable: isCardLoaded
                ? TodaysQuestionCheck.Openable(day: today, partnerHasAnswered: partnerHasAnswered)
                : nil
        )
    }

    @Test func firstOpeningOfTheDayOpensInPlaceOnceTheLaunchScreenFades() {
        let yesterday = TodaysQuestionOpening(day: "2026-11-14", partnerHadAnswered: true)

        #expect(check(visit: .starting).action(lastOpening: yesterday, now: since) == .startWindow)
        #expect(
            check(isIntroComplete: false).action(lastOpening: yesterday, now: since) == .openInPlace
        )
        #expect(check().action(lastOpening: nil, now: since) == .openInPlace)
    }

    @Test func firstOpeningWaitsForTheCardWithinTheWindow() {
        let deadline = since + TodaysQuestionCheck.window

        #expect(check(isCardLoaded: false).action(lastOpening: nil, now: since) == .wait(until: deadline))
        #expect(check().action(lastOpening: nil, now: deadline) == .decide)
    }

    @Test func secondOpeningWaitsForThePartnersAnswerAndZoomsOnceHomeIsAtRest() {
        let openedToday = TodaysQuestionOpening(day: today, partnerHadAnswered: false)
        let deadline = since + TodaysQuestionCheck.window

        #expect(check().action(lastOpening: openedToday, now: since) == .wait(until: deadline))
        #expect(
            check(isIntroComplete: false, partnerHasAnswered: true)
                .action(lastOpening: openedToday, now: since) == .wait(until: deadline)
        )
        #expect(check(partnerHasAnswered: true).action(lastOpening: openedToday, now: since) == .openWithZoom)

        let openedAfterPartner = TodaysQuestionOpening(day: today, partnerHadAnswered: true)
        #expect(
            check(partnerHasAnswered: true).action(lastOpening: openedAfterPartner, now: since)
                == .wait(until: deadline)
        )
    }

    @Test func nothingOpensWhileLockedOrAwayFromHome() {
        #expect(check(visit: .starting, isAppReady: false).action(lastOpening: nil, now: since) == .none)
        #expect(check(isAppReady: false).action(lastOpening: nil, now: since) == .none)
        #expect(check(isHomeInFront: false).action(lastOpening: nil, now: since) == .decide)
    }

    @Test func aDestinationInTheVisitDecidesItAndClosesTheQuestionItOpened() {
        #expect(check(visit: .opened).action(lastOpening: nil, now: since) == .none)
        #expect(check(visit: .decided).action(lastOpening: nil, now: since) == .none)

        #expect(TodaysQuestionVisit.opened.destinationClosesQuestion(opensTodaysQuestion: false))
        #expect(!TodaysQuestionVisit.opened.destinationClosesQuestion(opensTodaysQuestion: true))
        #expect(!TodaysQuestionVisit.starting.destinationClosesQuestion(opensTodaysQuestion: false))
        #expect(!TodaysQuestionVisit.ready(since: since).destinationClosesQuestion(opensTodaysQuestion: false))
    }
}
