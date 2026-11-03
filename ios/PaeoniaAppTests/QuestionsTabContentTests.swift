import Foundation
import Testing
@testable import PaeoniaApp

struct QuestionsTabContentTests {
    private let now = TestDailyChallengeIDs.answerDate

    private func question(
        id: UUID = UUID(), questionID: UUID = UUID(), seededAt: Date,
        partnerAnsweredAt: Date, ownAnswered: Bool = true, current: Bool = false
    ) -> DailyChallengeQuestion {
        DailyChallengeQuestion(
            id: id, coupleDayID: UUID(), coupleID: TestDailyChallengeIDs.couple,
            localDate: "2026-06-27", effectiveLocalDate: "2026-06-27",
            startsAt: seededAt, endsAt: TestDailyChallengeIDs.endsAt,
            status: .active, questionID: questionID, questionVersionID: UUID(), questionKey: "test",
            prompt: "Question", shortPrompt: "Question", answerKinds: [.text],
            ownAnswer: ownAnswered ? DailyQuestionAnswerSummary(id: UUID(), answeredAt: seededAt) : nil,
            partnerAnswer: DailyQuestionAnswerSummary(id: UUID(), answeredAt: partnerAnsweredAt),
            canViewPartnerAnswer: ownAnswered, ownAnswerDetail: nil, partnerAnswerDetail: nil,
            isCurrentDay: current
        )
    }

    private func content(
        current: [DailyChallengeQuestion] = [], history: [DailyChallengeQuestion] = [],
        conversations: [SubjectConversation] = [], unreadMessageAt: Date? = nil
    ) -> QuestionsTabContent {
        QuestionsTabContent(
            current: current, topics: [], history: history, conversations: conversations,
            today: "2026-06-27", timeZone: .gmt,
            attentionDate: { $0.attentionDate(seen: [], unreadMessageAt: unreadMessageAt) }
        )
    }

    @Test func theNewestUnreadMessageWinsEvenWhenItsStoryIsOldest() {
        let old = storyConversation(postedAt: now - 10 * 86_400, isUnread: true)
        let recent = storyConversation(postedAt: now - 600, isUnread: true)
        let summary = ThreadChatSummary(
            threadID: old.summary.threadID, coupleID: old.summary.coupleID, subject: old.summary.subject,
            createdAt: old.summary.createdAt, updatedAt: now, lastMessageID: UUID(), lastMessageAt: now,
            lastMessageSenderUserID: TestDailyChallengeIDs.partnerUser, lastMessageBody: "New reply"
        )
        let oldWithNewMessage = SubjectConversation(subject: old.subject, summary: summary, isUnread: true)

        #expect(content(conversations: [recent, oldWithNewMessage]).attention.map(\.id)
            == [old.id, recent.id])
    }

    @Test func awaitingAnswersAndAnswersToOpenUseTheSameActivityOrder() {
        let awaiting = question(seededAt: now - 600, partnerAnsweredAt: now - 300, ownAnswered: false, current: true)
        let toOpen = question(seededAt: now - 600, partnerAnsweredAt: now, current: true)
        #expect(content(current: [awaiting, toOpen]).attention.map(\.id) == [toOpen.id, awaiting.id])
    }

    @Test func aRecurringQuestionHasOneAttentionCardFromItsNewestRound() {
        let questionID = UUID()
        let oldLateAnswer = question(questionID: questionID, seededAt: now - 3 * 86_400, partnerAnsweredAt: now)
        let newestRound = question(questionID: questionID, seededAt: now - 86_400, partnerAnsweredAt: now - 600)
        let result = content(history: [oldLateAnswer, newestRound], unreadMessageAt: now + 60)

        #expect(result.attention.map(\.id) == [newestRound.id])
        #expect(result.shownQuestionIDs == [newestRound.id])
    }

    @Test func anExpiredUnseenDailyAnswerIsQuietUntilItsChatHasANewMessage() {
        let old = question(seededAt: now - 86_400, partnerAnsweredAt: now - 600)
        #expect(old.hasNewPartnerAnswer(seen: []))
        #expect(content(history: [old]).attention.isEmpty)
        #expect(content(history: [old], unreadMessageAt: now).attention.map(\.id) == [old.id])
    }

    @Test func currentReadStateWinsOverAStaleCopyInHistory() {
        let old = question(seededAt: now - 600, partnerAnsweredAt: now, current: true)
        var seen = old
        seen.partnerAnswerSeenAt = now + 60
        let result = content(current: [seen], history: [old])

        #expect(result.attention.isEmpty)
        #expect(result.recent.map(\.id) == [old.id])
    }
}
