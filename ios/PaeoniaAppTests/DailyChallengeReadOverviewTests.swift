import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeReadOverviewTests {
    @Test func readOverviewSeparatesExpiredDailyAnswersFromCurrentActivity() {
        let t1 = TestDailyChallengeIDs.answerDate
        let t2 = t1.addingTimeInterval(3_600)
        let t3 = t2.addingTimeInterval(3_600)
        let awaiting = UUID()
        let today = UUID()
        let finished = UUID()

        let snapshot = makeDailySnapshot(rows: [
            // An earlier day's question still waiting for the user, answered EARLIEST of
            // all, so pure recency would bury it last. Pinning must float it to the top.
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay,
                localDate: "2026-06-26",
                instanceID: awaiting,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: t1,
                isCurrentDay: false
            ),
            // Today's question, answered by the user most recently (no reply yet).
            dailyQuestionRow(
                instanceID: today,
                ownAnswerID: UUID(),
                ownAnsweredAt: t3
            ),
            // A finished exchange in the middle.
            dailyQuestionRow(
                coupleDayID: UUID(),
                localDate: "2026-06-25",
                instanceID: finished,
                ownAnswerID: UUID(),
                ownAnsweredAt: t2,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: t2,
                canViewPartnerAnswer: true,
                isCurrentDay: false
            ),
        ])

        let quiet = QuestionsTabContent(
            current: snapshot.questions, topics: [], history: [], conversations: [],
            today: "2026-06-27", timeZone: .gmt,
            attentionDate: { $0.attentionDate(seen: [], unreadMessageAt: nil) }
        )
        #expect(quiet.attention.isEmpty)
        #expect(quiet.recent.map(\.id) == [today, finished, awaiting])

        let withMessage = QuestionsTabContent(
            current: snapshot.questions, topics: [], history: [], conversations: [],
            today: "2026-06-27", timeZone: .gmt,
            attentionDate: { $0.attentionDate(seen: [], unreadMessageAt: $0.id == finished ? t3 : nil) }
        )
        #expect(withMessage.attention.map(\.id) == [finished])
        #expect(withMessage.recent.map(\.id) == [today, awaiting])
    }

    @Test func todaysMemoryAndStoryChatsJoinTodaysListAndOlderUnreadChatsRankWithTheNew() {
        let t0 = TestDailyChallengeIDs.answerDate
        let t1 = t0.addingTimeInterval(600)
        let t2 = t1.addingTimeInterval(600)
        let t3 = t2.addingTimeInterval(600)
        let awaiting = UUID()
        let newAnswer = UUID()
        let recent = UUID()
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay, localDate: "2026-06-26",
                instanceID: awaiting,
                partnerAnswerID: UUID(), partnerAnsweredAt: t0.addingTimeInterval(-3_600), isCurrentDay: false
            ),
            dailyQuestionRow(
                instanceID: newAnswer, ownAnswerID: UUID(), ownAnsweredAt: t0,
                partnerAnswerID: UUID(), partnerAnsweredAt: t1, canViewPartnerAnswer: true
            ),
            dailyQuestionRow(
                coupleDayID: UUID(), localDate: "2026-06-25",
                instanceID: recent,
                ownAnswerID: UUID(), ownAnsweredAt: t3, isCurrentDay: false
            ),
        ])
        let unreadStory = storyConversation(postedAt: t0, isUnread: true)
        let readStory = storyConversation(postedAt: t2)
        let earlierStory = storyConversation(postedAt: t0.addingTimeInterval(-2 * 86_400), isUnread: true)
        // Added today, so on today's list even though the memory is dated years back.
        let unreadMemory = memoryConversation(addedAt: t2, memoryDate: "2019-07-14", isUnread: true)
        let readMemory = memoryConversation(addedAt: t0.addingTimeInterval(-600), memoryDate: "2019-07-14")
        let earlierMemory = memoryConversation(
            addedAt: t0.addingTimeInterval(-3 * 86_400),
            memoryDate: MemoryTimeline.localDateString(for: t0),
            isUnread: true
        )

        let content = QuestionsTabContent(
            current: snapshot.questions, topics: [], history: [],
            conversations: [readStory, earlierStory, unreadStory, readMemory, unreadMemory, earlierMemory],
            today: MemoryTimeline.localDateString(for: t0, timeZone: .gmt), timeZone: .gmt,
            attentionDate: { $0.attentionDate(seen: [], unreadMessageAt: nil) }
        )
        #expect(content.attention.map(\.id) == [unreadMemory.id, newAnswer, unreadStory.id,
                                                earlierStory.id, earlierMemory.id])
        #expect(content.recent.map(\.id) == [recent, readStory.id, readMemory.id, awaiting])
    }

    @Test func readingAnOlderConversationReturnsItToHistoryWithoutDuplicates() {
        let now = TestDailyChallengeIDs.answerDate
        let today = MemoryTimeline.localDateString(for: now)
        let unread = storyConversation(postedAt: now.addingTimeInterval(-86_400), isUnread: true)
        let read = SubjectConversation(subject: unread.subject, summary: unread.summary, isUnread: false)

        func content(_ conversation: SubjectConversation) -> QuestionsTabContent {
            QuestionsTabContent(
                current: [], topics: [], history: [], conversations: [conversation],
                today: today, timeZone: .current, attentionDate: { _ in nil }
            )
        }
        #expect(content(unread).attention.map(\.id) == [unread.id])
        #expect(content(read).attention.isEmpty)
        #expect(content(read).recent.isEmpty)
        let afterReading = DailyChallengeHistory.adding([read], before: today, to: [])
        #expect(afterReading.flatMap(\.rows).map(\.id) == [read.id])
    }

    @Test func aPartnerAnswerIsNewUntilYouHaveSeenIt() throws {
        let t1 = TestDailyChallengeIDs.answerDate
        let t2 = t1.addingTimeInterval(3_600)
        let answeredFirst = UUID()
        let answeredSecond = UUID()
        let hidden = UUID()
        let snapshot = makeDailySnapshot(rows: [
            // You answered, then your partner did.
            dailyQuestionRow(
                instanceID: answeredFirst,
                ownAnswerID: UUID(), ownAnsweredAt: t1, partnerAnswerID: UUID(), partnerAnsweredAt: t2,
                canViewPartnerAnswer: true
            ),
            // You answered second, and the reveal hasn't shown the reply yet.
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay, localDate: "2026-06-26",
                instanceID: answeredSecond,
                ownAnswerID: UUID(), ownAnsweredAt: t2, partnerAnswerID: UUID(), partnerAnsweredAt: t1,
                canViewPartnerAnswer: true, isCurrentDay: false
            ),
            // Your partner answered, but you can't see it yet.
            dailyQuestionRow(
                coupleDayID: UUID(), localDate: "2026-06-25",
                instanceID: hidden,
                ownAnswerID: UUID(), ownAnsweredAt: t1, partnerAnswerID: UUID(), partnerAnsweredAt: t2,
                isCurrentDay: false
            ),
        ])
        let byID = Dictionary(uniqueKeysWithValues: snapshot.questions.map { ($0.id, $0) })
        let mine = try #require(byID[answeredFirst])

        #expect(mine.hasNewPartnerAnswer(seen: []))
        #expect(!mine.hasNewPartnerAnswer(seen: [mine.id]))
        // Seen on another device.
        var seenElsewhere = mine
        seenElsewhere.partnerAnswerSeenAt = t2
        #expect(!seenElsewhere.hasNewPartnerAnswer(seen: []))
        #expect(byID[answeredSecond]?.hasNewPartnerAnswer(seen: []) == true)
        #expect(byID[hidden]?.hasNewPartnerAnswer(seen: []) == false)
    }

    @Test func carriedForwardQuestionsSortBelowCurrentDayQuestions() {
        let previousStart = TestDailyChallengeIDs.startsAt.addingTimeInterval(-86_400)
        let previousEnd = TestDailyChallengeIDs.startsAt
        let olderStart = previousStart.addingTimeInterval(-86_400)
        let currentPartnerAnswer = TestDailyChallengeIDs.answerDate.addingTimeInterval(60)
        let olderPartnerAnswer = TestDailyChallengeIDs.answerDate.addingTimeInterval(-86_400)
        let today = UUID()
        let yesterday = UUID()
        let twoDaysAgo = UUID()

        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                coupleDayID: UUID(), localDate: "2026-06-25", startsAt: olderStart,
                endsAt: previousStart, instanceID: twoDaysAgo,
                partnerAnswerID: UUID(), partnerAnsweredAt: olderPartnerAnswer, isCurrentDay: false
            ),
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay, localDate: "2026-06-26", startsAt: previousStart,
                endsAt: previousEnd, instanceID: yesterday,
                partnerAnswerID: UUID(), partnerAnsweredAt: olderPartnerAnswer, isCurrentDay: false
            ),
            dailyQuestionRow(
                instanceID: today,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: currentPartnerAnswer, isCurrentDay: true
            ),
        ])

        #expect(snapshot.questionsAwaitingAnswer.map(\.id) == [today, yesterday, twoDaysAgo])
        #expect(snapshot.earlierQuestionsAwaitingAnswer.map(\.id) == [yesterday, twoDaysAgo])
    }

    @Test func homeCardIgnoresCarriedForwardQuestionsWhenTodayHasNotStarted() {
        let previousStart = TestDailyChallengeIDs.startsAt.addingTimeInterval(-86_400)
        let previousEnd = TestDailyChallengeIDs.startsAt

        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay,
                localDate: "2026-06-26",
                startsAt: previousStart,
                endsAt: previousEnd,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: previousStart.addingTimeInterval(600),
                isCurrentDay: false
            ),
        ])

        #expect(snapshot.hasAnyQuestions)
        #expect(snapshot.todayQuestion == nil)
        #expect(snapshot.earlierQuestionsAwaitingAnswer.count == 1)
        #expect(snapshot.homeCardState.kind == .noChallenge)
    }
}
