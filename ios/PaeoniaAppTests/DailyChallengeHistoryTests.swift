import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeHistoryTests {
    private static let day1 = "2026-06-25"
    private static let day2 = "2026-06-26"
    private static let day3 = "2026-06-27"

    /// An answered own-question row for `localDate`, answered at `answeredAt`.
    private func answeredOwnRow(
        localDate: String,
        slotNumber: Int,
        answeredAt: Date,
        ownAnswerID: UUID = UUID()
    ) -> DailyQuestionRow {
        // A couple day is unique per date; grouping keys on localDate, so a fresh
        // couple-day id per row keeps the fixtures realistic without affecting it.
        dailyQuestionRow(
            coupleDayID: UUID(),
            localDate: localDate,
            slotNumber: slotNumber,
            seededForUserID: TestDailyChallengeIDs.currentUser,
            status: "answered",
            ownAnswerID: ownAnswerID,
            ownAnsweredAt: answeredAt
        )
    }

    private func historyQuestions(
        _ rows: [DailyQuestionRow],
        details: [DailyAnswerDetailRow] = []
    ) -> [DailyChallengeQuestion] {
        DailyChallengeQuestion.list(
            currentUserID: TestDailyChallengeIDs.currentUser,
            rows: rows,
            answerDetails: details,
            locale: Locale(identifier: "en_US")
        )
    }

    @Test func groupsByLocalDateNewestFirst() {
        let questions = historyQuestions([
            answeredOwnRow(localDate: Self.day1, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            answeredOwnRow(localDate: Self.day2, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            answeredOwnRow(localDate: Self.day2, slotNumber: 2, answeredAt: TestDailyChallengeIDs.answerDate),
        ])

        let days = DailyChallengeHistory.grouped(questions)

        #expect(days.map(\.localDate) == [Self.day3, Self.day2, Self.day1])
        #expect(days.first(where: { $0.localDate == Self.day2 })?.questions.count == 2)
        #expect(days.first(where: { $0.localDate == Self.day3 })?.questions.count == 1)
    }

    @Test func ordersQuestionsWithinADayByLatestAnswerFirst() {
        let early = TestDailyChallengeIDs.answerDate
        let late = early.addingTimeInterval(3_600)

        // Slot 1 answered later than slot 2, so the most-recently-answered comes first
        // regardless of slot order.
        let questions = historyQuestions([
            answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: late),
            answeredOwnRow(localDate: Self.day3, slotNumber: 2, answeredAt: early),
        ])

        let days = DailyChallengeHistory.grouped(questions)

        #expect(days.count == 1)
        #expect(days[0].questions.map(\.slotNumber) == [1, 2])
    }

    @Test func usesLatestOfOwnAndPartnerAnswerAsSortKey() {
        let early = TestDailyChallengeIDs.answerDate
        let mid = early.addingTimeInterval(1_800)
        let late = early.addingTimeInterval(3_600)

        // Question A's own answer is the earliest of everything, but its partner reply
        // is the latest — so by "latest answer" it must sort ahead of question B, whose
        // only (own) answer lands in the middle. This fails if the key used the
        // earliest/own answer instead of the latest of the two.
        let questionA = dailyQuestionRow(
            localDate: Self.day3,
            slotNumber: 1,
            seededForUserID: TestDailyChallengeIDs.currentUser,
            status: "answered",
            ownAnswerID: UUID(),
            ownAnsweredAt: early,
            partnerAnswerID: UUID(),
            partnerAnsweredAt: late,
            canViewPartnerAnswer: true
        )
        let questionB = answeredOwnRow(localDate: Self.day3, slotNumber: 2, answeredAt: mid)

        let days = DailyChallengeHistory.grouped(historyQuestions([questionB, questionA]))

        #expect(days.count == 1)
        #expect(days[0].questions.map(\.slotNumber) == [1, 2])
    }

    @Test func placesQuestionInLatestAnswerDayNotInstanceDay() {
        // Instance seeded yesterday (day2): the partner answered before midnight, the
        // viewer answered after midnight today (day3). The backend hands us that latest
        // day as effectiveLocalDate, and grouping must bucket the exchange under it —
        // not under the instance's seed day — so it never hides on the previous day.
        let beforeMidnight = TestDailyChallengeIDs.answerDate
        let afterMidnight = beforeMidnight.addingTimeInterval(3 * 3_600)

        let carried = dailyQuestionRow(
            localDate: Self.day2,
            effectiveLocalDate: Self.day3,
            slotNumber: 1,
            seededForUserID: TestDailyChallengeIDs.partnerUser,
            status: "answered",
            ownAnswerID: UUID(),
            ownAnsweredAt: afterMidnight,
            partnerAnswerID: UUID(),
            partnerAnsweredAt: beforeMidnight,
            canViewPartnerAnswer: true
        )

        let days = DailyChallengeHistory.grouped(historyQuestions([carried]))

        #expect(days.map(\.localDate) == [Self.day3])
        #expect(days.first?.questions.count == 1)
    }

    @Test func parsesLocalDateToUTCMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let expected = calendar.date(from: DateComponents(year: 2_026, month: 6, day: 27))

        #expect(DailyChallengeHistory.parseLocalDate("2026-06-27") == expected)
        #expect(DailyChallengeHistory.parseLocalDate("not-a-date") == nil)
    }

    @Test func serviceLoadHistoryMergesRowsAndDetailsInTwoCalls() async throws {
        let ownAnswerID = UUID()
        let gateway = RecordingDailyChallengeReadGateway(
            rows: [],
            historyRows: [
                answeredOwnRow(
                    localDate: Self.day3,
                    slotNumber: 1,
                    answeredAt: TestDailyChallengeIDs.answerDate,
                    ownAnswerID: ownAnswerID
                ),
            ],
            historyDetails: [
                dailyAnswerDetail(answerID: ownAnswerID, isOwnAnswer: true, textBody: "A quiet morning together"),
            ]
        )
        let service = DailyChallengeService(gateway: gateway, locale: Locale(identifier: "en_US"))

        let questions = try await service.loadHistory(currentUserID: TestDailyChallengeIDs.currentUser)

        #expect(questions.count == 1)
        #expect(questions.first?.ownAnswerDetail?.textBody == "A quiet morning together")
        #expect(await gateway.historyQuestionLoadCount == 1)
        #expect(await gateway.historyDetailLoadCount == 1)
    }

    @MainActor
    @Test func viewModelReloadFailureKeepsContentAndShowsBanner() async {
        let service = RecordingDailyChallengeService(
            snapshots: [],
            historyQuestions: historyQuestions([
                answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            ]),
            historyReloadError: URLError(.timedOut)
        )
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: TestDailyChallengeIDs.currentUser
        )

        await viewModel.load()
        await viewModel.load()

        guard case let .content(days) = viewModel.state else {
            Issue.record("Expected content to remain after a failed reload, got \(viewModel.state)")
            return
        }
        #expect(days.count == 1)
        #expect(viewModel.notice == .loadFailed(.other))
    }
}
