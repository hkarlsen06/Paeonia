import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeHistoryTests {
    private static let day1 = "2026-06-25"
    private static let day2 = "2026-06-26"
    private static let day3 = "2026-06-27"

    private func answerInstant(on day: String, hour: Int = 12) -> Date {
        (DailyChallengeHistory.parseLocalDate(day) ?? .distantPast).addingTimeInterval(Double(hour) * 3_600)
    }

    /// A row the user answered on `localDate`, at `answeredAt`.
    private func answeredOwnRow(
        localDate: String,
        answeredAt: Date,
        ownAnswerID: UUID = UUID()
    ) -> DailyQuestionRow {
        // Each seeded day has its own id; grouping uses the actual latest answer instant.
        dailyQuestionRow(
            coupleDayID: UUID(),
            localDate: localDate,
            ownAnswerID: ownAnswerID,
            ownAnsweredAt: answeredAt
        )
    }

    private func historyQuestions(
        _ rows: [DailyQuestionRow],
        details: [DailyAnswerDetailRow] = []
    ) -> [DailyChallengeQuestion] {
        DailyChallengeQuestion.list(
            rows: rows,
            answerDetails: details,
            locale: Locale(identifier: "en_US")
        )
    }

    @Test func groupsByLocalDateNewestFirst() {
        let questions = historyQuestions([
            answeredOwnRow(localDate: Self.day1, answeredAt: answerInstant(on: Self.day1)),
            answeredOwnRow(localDate: Self.day3, answeredAt: answerInstant(on: Self.day3)),
            answeredOwnRow(localDate: Self.day2, answeredAt: answerInstant(on: Self.day2)),
            answeredOwnRow(localDate: Self.day2, answeredAt: answerInstant(on: Self.day2)),
        ])

        let days = DailyChallengeHistory.grouped(questions)

        #expect(days.map(\.localDate) == [Self.day3, Self.day2, Self.day1])
        #expect(days.first(where: { $0.localDate == Self.day2 })?.rows.count == 2)
        #expect(days.first(where: { $0.localDate == Self.day3 })?.rows.count == 1)
    }

    @Test func ordersQuestionsWithinADayByLatestAnswerFirst() {
        let early = TestDailyChallengeIDs.answerDate
        let late = early.addingTimeInterval(3_600)

        // Two exchanges finished on the same day: the most recently answered comes
        // first, whatever order the rows arrive in.
        let earlyRow = answeredOwnRow(localDate: Self.day3, answeredAt: early)
        let lateRow = answeredOwnRow(localDate: Self.day3, answeredAt: late)
        let questions = historyQuestions([earlyRow, lateRow])

        let days = DailyChallengeHistory.grouped(questions)

        #expect(days.count == 1)
        #expect(days[0].rows.map(\.id) == [lateRow.instanceID, earlyRow.instanceID])
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
            ownAnswerID: UUID(),
            ownAnsweredAt: early,
            partnerAnswerID: UUID(),
            partnerAnsweredAt: late,
            canViewPartnerAnswer: true
        )
        let questionB = answeredOwnRow(localDate: Self.day3, answeredAt: mid)

        let days = DailyChallengeHistory.grouped(historyQuestions([questionB, questionA]))

        #expect(days.count == 1)
        #expect(days[0].rows.map(\.id) == [questionA.instanceID, questionB.instanceID])
    }

    @Test func placesQuestionInLatestAnswerDayNotInstanceDay() {
        // The shared date follows the last answer's instant rather than the seed day
        // or the backend's historical date label.
        let beforeMidnight = answerInstant(on: Self.day2, hour: 23)
        let afterMidnight = beforeMidnight.addingTimeInterval(2 * 3_600)

        let carried = dailyQuestionRow(
            localDate: Self.day2,
            effectiveLocalDate: Self.day3,
            ownAnswerID: UUID(),
            ownAnsweredAt: afterMidnight,
            partnerAnswerID: UUID(),
            partnerAnsweredAt: beforeMidnight,
            canViewPartnerAnswer: true
        )

        let days = DailyChallengeHistory.grouped(historyQuestions([carried]))

        #expect(days.map(\.localDate) == [Self.day3])
        #expect(days.first?.rows.count == 1)
    }

    @Test func storyChatsGoUnderTheDayTheirStoryWasPosted() {
        let posted = TestDailyChallengeIDs.answerDate
        let storyDay = MemoryTimeline.localDateString(for: posted, timeZone: .gmt)
        let question = answeredOwnRow(localDate: storyDay, answeredAt: posted.addingTimeInterval(-3_600))
        let sameDay = storyConversation(postedAt: posted)
        let olderDay = storyConversation(postedAt: posted.addingTimeInterval(-3 * 86_400))
        let fromToday = storyConversation(postedAt: posted.addingTimeInterval(2 * 86_400))
        let today = fromToday.localDate

        let days = DailyChallengeHistory.adding(
            [sameDay, olderDay, fromToday],
            before: today,
            to: DailyChallengeHistory.grouped(historyQuestions([question]))
        )

        // The story from today stays out, the one posted on a day without questions gets
        // that day, and the other sorts by time with its day's question.
        #expect(days.map(\.localDate) == [storyDay, olderDay.localDate])
        #expect(days[0].rows.map(\.id) == [sameDay.id, question.instanceID])
        #expect(days[1].rows.map(\.id) == [olderDay.id])
    }

    @Test func memoryChatsGoUnderTheDayTheMemoryWasAddedNotItsDate() {
        let added = TestDailyChallengeIDs.answerDate
        let addedDay = MemoryTimeline.localDateString(for: added, timeZone: .gmt)
        let question = answeredOwnRow(localDate: addedDay, answeredAt: added.addingTimeInterval(3_600))
        let story = storyConversation(postedAt: added.addingTimeInterval(1_800))
        let oldMemory = memoryConversation(addedAt: added, memoryDate: "2019-07-14")
        let addedToday = memoryConversation(addedAt: added.addingTimeInterval(2 * 86_400), memoryDate: "2019-07-14")

        let days = DailyChallengeHistory.adding(
            [oldMemory, addedToday, story],
            before: addedToday.localDate,
            to: DailyChallengeHistory.grouped(historyQuestions([question]))
        )

        // A memory dated years back sits on the day it was added, by time with that day's
        // question and story. The one added today stays out of the earlier days.
        #expect(days.map(\.localDate) == [addedDay])
        #expect(days[0].rows.map(\.id) == [question.instanceID, story.id, oldMemory.id])
    }

    @Test func questionAndConversationDatesUseTheSameSharedZone() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-03T23:30:00Z"))
        let question = answeredOwnRow(localDate: "2026-11-02", answeredAt: instant)
        let story = storyConversation(postedAt: instant)
        let memory = memoryConversation(addedAt: instant, memoryDate: "2019-01-01")
        let days = DailyChallengeHistory.adding(
            [story, memory], before: "2026-11-04",
            to: DailyChallengeHistory.grouped(historyQuestions([question]), timeZone: zone),
            timeZone: zone
        )
        #expect(days.map(\.localDate) == ["2026-11-03"])
        #expect(Set(days.flatMap(\.rows).map(\.id)) == [question.instanceID, story.id, memory.id])
        let easternZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        #expect(MemoryTimeline.localDateString(for: instant, timeZone: easternZone) == "2026-11-04")
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
                answeredOwnRow(localDate: Self.day3, answeredAt: TestDailyChallengeIDs.answerDate),
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
