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
            messageDate: { _ in unreadMessageAt }
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

        #expect(content(conversations: [recent, oldWithNewMessage]).recent.map(\.id)
            == [old.id, recent.id])
    }

    @Test func unansweredQuestionsStayAboveNewerAnsweredQuestions() {
        let awaiting = question(seededAt: now - 600, partnerAnsweredAt: now - 300, ownAnswered: false, current: true)
        let toOpen = question(seededAt: now - 600, partnerAnsweredAt: now, current: true)
        #expect(content(current: [awaiting, toOpen]).waitingForYou.map(\.id) == [awaiting.id])
        #expect(content(current: [awaiting, toOpen]).recent.map(\.id) == [toOpen.id])
    }

    @Test func aRecurringQuestionHasOneConversationCardFromItsNewestRound() {
        let questionID = UUID()
        let oldLateAnswer = question(questionID: questionID, seededAt: now - 3 * 86_400, partnerAnsweredAt: now)
        let newestRound = question(questionID: questionID, seededAt: now - 86_400, partnerAnsweredAt: now - 600)
        let result = content(history: [oldLateAnswer, newestRound], unreadMessageAt: now + 60)

        #expect(result.recent.map(\.id) == [newestRound.id])
        #expect(result.waitingForYou.isEmpty)
    }

    @Test func olderAnsweredQuestionsStayInTheConversationList() {
        let old = question(seededAt: now - 86_400, partnerAnsweredAt: now - 600)
        #expect(old.hasNewPartnerAnswer(seen: []))
        #expect(content(history: [old]).waitingForYou.isEmpty)
        #expect(content(history: [old], unreadMessageAt: now).recent.map(\.id) == [old.id])
    }

    @Test func aLateAnswerToAnOlderRoundDeterminesTheConversationCard() {
        let questionID = UUID()
        let late = question(questionID: questionID, seededAt: now - 3 * 86_400, partnerAnsweredAt: now)
        let newerRound = question(questionID: questionID, seededAt: now - 86_400, partnerAnsweredAt: now - 600)
        let other = question(seededAt: now - 300, partnerAnsweredAt: now - 60)
        let result = content(history: [late, newerRound, other])
        #expect(result.recent.map(\.id) == [late.id, other.id])
    }

    @Test func currentReadStateWinsOverAStaleCopyInHistory() {
        let old = question(seededAt: now - 600, partnerAnsweredAt: now, current: true)
        var seen = old
        seen.partnerAnswerSeenAt = now + 60
        let result = content(current: [seen], history: [old])

        #expect(result.waitingForYou.isEmpty)
        #expect(result.recent.map(\.id) == [old.id])
    }

    @Test func aReadMessageKeepsAnOldQuestionAboveNewerAnswers() {
        let old = question(seededAt: now - 10 * 86_400, partnerAnsweredAt: now - 9 * 86_400)
        let newer = question(seededAt: now - 600, partnerAnsweredAt: now - 300)
        let result = QuestionsTabContent(
            current: [], topics: [], history: [newer, old], conversations: [],
            messageDate: { $0.id == old.id ? now : nil }
        )
        #expect(result.recent.map(\.id) == [old.id, newer.id])
        #expect(result.waitingForYou.isEmpty)
    }

    @Test func anOlderUnansweredRoundRemainsDiscoverableBesideANewerCompletedRound() {
        let questionID = UUID()
        let waiting = question(questionID: questionID, seededAt: now - 86_400,
                               partnerAnsweredAt: now - 3_600, ownAnswered: false)
        let answered = question(questionID: questionID, seededAt: now - 600, partnerAnsweredAt: now)
        let result = content(current: [waiting, answered])
        #expect(result.waitingForYou.map(\.id) == [waiting.id])
        #expect(result.recent.isEmpty)
    }

    @Test func answerPreviewsNeverExposeAnUnrevealedPartnerAnswer() {
        let revealed = previewHistoryQuestion(
            localDate: "2026-06-27", prompt: "Question", ownText: "My answer", partnerText: "Private answer"
        )
        var question = DailyChallengeQuestion(
            id: revealed.id, coupleDayID: revealed.coupleDayID, coupleID: revealed.coupleID,
            localDate: revealed.localDate, effectiveLocalDate: revealed.effectiveLocalDate,
            startsAt: revealed.startsAt, endsAt: revealed.endsAt, status: revealed.status,
            questionID: revealed.questionID, questionVersionID: revealed.questionVersionID,
            questionKey: revealed.questionKey, prompt: revealed.prompt, shortPrompt: revealed.shortPrompt,
            answerKinds: revealed.answerKinds, ownAnswer: revealed.ownAnswer, partnerAnswer: revealed.partnerAnswer,
            canViewPartnerAnswer: false, ownAnswerDetail: revealed.ownAnswerDetail,
            partnerAnswerDetail: revealed.partnerAnswerDetail, isCurrentDay: false
        )
        let participants = DailyChallengeParticipants(partnerDisplayName: "Robin")
        let ownPreview = question.answerPreview(participants: participants)
        #expect(ownPreview?.contains("My answer") == true)
        #expect(ownPreview?.contains("Private answer") == false)
        question.ownAnswer = nil
        question.ownAnswerDetail = nil
        #expect(question.answerPreview(participants: participants) == nil)
    }
}
