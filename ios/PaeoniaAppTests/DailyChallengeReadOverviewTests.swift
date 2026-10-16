import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeReadOverviewTests {
    @Test func readOverviewOrdersPartnerQuestionsThenOwnQuestionsByPartnerAnswer() {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID()
            ),
            dailyQuestionRow(
                slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID(), partnerAnswerID: UUID(), partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            dailyQuestionRow(
                slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID()
            ),
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.partnerUser, partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            dailyQuestionRow(
                slotNumber: 2, seededForUserID: TestDailyChallengeIDs.partnerUser, ownAnswerID: UUID(),
                partnerAnswerID: UUID(), partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            dailyQuestionRow(
                slotNumber: 3, seededForUserID: TestDailyChallengeIDs.partnerUser, partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])

        let partnerReadQuestions = snapshot.partnerQuestionsForReadOverview
        #expect(partnerReadQuestions.map(\.slotNumber) == [1, 3, 2])
        #expect(partnerReadQuestions.prefix(2).allSatisfy { $0.isAvailableToAnswer })
        #expect(partnerReadQuestions.last?.isAvailableToAnswer == false)

        let ownReadQuestions = snapshot.ownQuestionsForReadOverview
        #expect(ownReadQuestions.map(\.slotNumber) == [2, 1, 3])
        #expect(ownReadQuestions.first?.hasPartnerAnswer == true)
    }

    @Test func readOverviewOrdersRevealedCardsByCompletionTimeNewestFirst() {
        let earlier = TestDailyChallengeIDs.answerDate
        let later = earlier.addingTimeInterval(3_600)

        let snapshot = makeDailySnapshot(rows: [
            // The partner's questions you've answered (revealed) sort by when YOU
            // answered, newest first → slot 2 (later) before slot 1 (earlier).
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.partnerUser, ownAnswerID: UUID(),
                ownAnsweredAt: earlier, partnerAnswerID: UUID(), partnerAnsweredAt: earlier, canViewPartnerAnswer: true
            ),
            dailyQuestionRow(
                slotNumber: 2, seededForUserID: TestDailyChallengeIDs.partnerUser, ownAnswerID: UUID(),
                ownAnsweredAt: later, partnerAnswerID: UUID(), partnerAnsweredAt: earlier, canViewPartnerAnswer: true
            ),
            // Your own questions the partner answered sort by when the PARTNER
            // answered, newest first → slot 4 (later) before slot 3 (earlier).
            dailyQuestionRow(
                slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID(), ownAnsweredAt: earlier, partnerAnswerID: UUID(), partnerAnsweredAt: earlier,
                canViewPartnerAnswer: true
            ),
            dailyQuestionRow(
                slotNumber: 4, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID(), ownAnsweredAt: earlier, partnerAnswerID: UUID(), partnerAnsweredAt: later,
                canViewPartnerAnswer: true
            ),
        ])

        #expect(snapshot.partnerQuestionsForReadOverview.map(\.slotNumber) == [2, 1])
        #expect(snapshot.ownQuestionsForReadOverview.map(\.slotNumber) == [4, 3])
    }

    @Test func readOverviewQuestionsPinAwaitingAnswerThenMostRecent() {
        let t1 = TestDailyChallengeIDs.answerDate
        let t2 = t1.addingTimeInterval(3_600)
        let t3 = t2.addingTimeInterval(3_600)

        let snapshot = makeDailySnapshot(rows: [
            // A partner question still waiting for the user — answered EARLIEST of all,
            // so pure recency would bury it last. Pinning must float it to the top.
            dailyQuestionRow(
                slotNumber: 3,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: t1
            ),
            // The user's own question, answered most recently (no reply yet).
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID(),
                ownAnsweredAt: t3
            ),
            // A finished partner exchange in the middle.
            dailyQuestionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                status: "answered",
                ownAnswerID: UUID(),
                ownAnsweredAt: t2,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: t2,
                canViewPartnerAnswer: true
            ),
        ])

        // One list: the to-do (slot 3) is pinned on top despite being the oldest, then
        // the rest by most recent answer (slot 1 at t3, slot 2 at t2). Pure recency
        // would have been [1, 2, 3].
        #expect(snapshot.readOverviewQuestions().map(\.slotNumber) == [3, 1, 2])

        // Something new on the oldest finished exchange (slot 2) moves it above the
        // timeline, but still below the to-do.
        #expect(
            snapshot.readOverviewQuestions(isNew: { $0.slotNumber == 2 }).map(\.slotNumber)
                == [3, 2, 1]
        )
    }

    @Test func aPartnerAnswerIsNewUntilYouHaveSeenIt() throws {
        let t1 = TestDailyChallengeIDs.answerDate
        let t2 = t1.addingTimeInterval(3_600)
        let snapshot = makeDailySnapshot(rows: [
            // Your question: you answered, then your partner did.
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID(), ownAnsweredAt: t1, partnerAnswerID: UUID(), partnerAnsweredAt: t2,
                canViewPartnerAnswer: true
            ),
            // Their question: you answered second, and the reveal hasn't shown the reply yet.
            dailyQuestionRow(
                slotNumber: 2, seededForUserID: TestDailyChallengeIDs.partnerUser, status: "answered",
                ownAnswerID: UUID(), ownAnsweredAt: t2, partnerAnswerID: UUID(), partnerAnsweredAt: t1,
                canViewPartnerAnswer: true
            ),
            // Your question: your partner answered, but you can't see it yet.
            dailyQuestionRow(
                slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID(), ownAnsweredAt: t1, partnerAnswerID: UUID(), partnerAnsweredAt: t2
            ),
        ])
        let bySlot = Dictionary(uniqueKeysWithValues: snapshot.questions.map { ($0.slotNumber, $0) })
        let mine = try #require(bySlot[1])

        #expect(mine.hasNewPartnerAnswer(seen: []))
        #expect(!mine.hasNewPartnerAnswer(seen: [mine.id]))
        // Seen on another device.
        var seenElsewhere = mine
        seenElsewhere.partnerAnswerSeenAt = t2
        #expect(!seenElsewhere.hasNewPartnerAnswer(seen: []))
        #expect(bySlot[2]?.hasNewPartnerAnswer(seen: []) == true)
        #expect(bySlot[3]?.hasNewPartnerAnswer(seen: []) == false)
    }

    /// Opening a chat marks the partner's answer seen, so the chat decides to play the
    /// reveal before that read.
    @MainActor
    @Test func aChatOpenedOnAnUnseenPartnerAnswerPlaysTheReveal() async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID(), partnerAnswerID: UUID(), partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                canViewPartnerAnswer: true
            ),
        ])
        let viewModel = DailyChallengeViewModel(
            service: RecordingDailyChallengeService(snapshots: [snapshot]),
            operationProvider: FixedDailyChallengeOperationProvider()
        )
        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.questions.first)

        await viewModel.prepareChat(for: question)
        #expect(viewModel.makeChatViewModel(question: question).revealsPartnerAnswer)

        viewModel.seenPartnerAnswerIDs.insert(question.id)
        await viewModel.prepareChat(for: question)
        #expect(!viewModel.makeChatViewModel(question: question).revealsPartnerAnswer)
    }

    @Test func carriedForwardQuestionsSortBelowCurrentDayQuestions() {
        let previousStart = TestDailyChallengeIDs.startsAt.addingTimeInterval(-86_400)
        let previousEnd = TestDailyChallengeIDs.startsAt
        let currentPartnerAnswer = TestDailyChallengeIDs.answerDate.addingTimeInterval(60)
        let olderPartnerAnswer = TestDailyChallengeIDs.answerDate.addingTimeInterval(-86_400)

        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay, localDate: "2026-06-26", startsAt: previousStart,
                endsAt: previousEnd, slotNumber: 1, seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(), partnerAnsweredAt: olderPartnerAnswer, isCurrentDay: false
            ),
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.partnerUser, partnerAnswerID: UUID(),
                partnerAnsweredAt: currentPartnerAnswer, isCurrentDay: true
            ),
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay, localDate: "2026-06-26", startsAt: previousStart,
                endsAt: previousEnd, slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered", ownAnswerID: UUID(), ownAnsweredAt: olderPartnerAnswer, isCurrentDay: false
            ),
            dailyQuestionRow(
                slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: UUID(), ownAnsweredAt: currentPartnerAnswer, isCurrentDay: true
            ),
        ])

        #expect(snapshot.partnerQuestionsForReadOverview.map(\.isCurrentDay) == [true, false])
        #expect(snapshot.ownQuestionsForReadOverview.map(\.isCurrentDay) == [true])
        #expect(snapshot.answerFlowQuestions.map(\.isCurrentDay) == [true, true, false])
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
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: previousStart.addingTimeInterval(600),
                isCurrentDay: false
            ),
        ])

        #expect(snapshot.hasAnyQuestions)
        #expect(!snapshot.hasAnyCurrentDayQuestions)
        #expect(snapshot.partnerQuestionsForReadOverview.count == 1)
        #expect(snapshot.homeCardState.kind == .noChallenge)
    }

    @Test func answerFlowOrdersOwnQuestionsThenAnswerablePartnerQuestions() {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser),
            dailyQuestionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
            // Partner's question that the partner answered: the current user can
            // still answer it, so it belongs at the end of the flow.
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])

        let flow = snapshot.answerFlowQuestions

        #expect(flow.count == 3)
        #expect(flow.prefix(2).map(\.slotNumber) == [1, 2])
        #expect(flow.prefix(2).allSatisfy { $0.origin == .own })
        #expect(flow.last?.origin == .partner)
        #expect(flow.last?.isAvailableToAnswer == true)
    }
}
