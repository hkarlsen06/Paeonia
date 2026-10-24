import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeMappingTests {
    @Test func completedDayFollowUpDependsOnThePartner() {
        func state(partnerAnswered: Bool, earlierWaiting: Bool) -> DailyChallengeCardState {
            DailyChallengeCardState(
                kind: .complete,
                hasPartnerAnsweredToday: partnerAnswered,
                hasEarlierQuestionsToAnswer: earlierWaiting
            )
        }

        // Earlier questions waiting for the user come first, even when the partner also
        // answered today.
        #expect(state(partnerAnswered: true, earlierWaiting: true).completeFollowUp == .earlierQuestionsToAnswer)
        #expect(state(partnerAnswered: false, earlierWaiting: false).completeFollowUp == .waitingForPartner)
        #expect(state(partnerAnswered: true, earlierWaiting: false).completeFollowUp == .bothAnswered)
    }

    @Test func partnerAnsweredUnrevealedQuestionCanBeAnsweredButBodyStaysHidden() throws {
        let partnerAnswerID = dailyFixedUUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                answerKinds: [.voice, .text],
                partnerAnswerID: partnerAnswerID,
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                canViewPartnerAnswer: false
            ),
        ])

        let question = try #require(snapshot.todayQuestion)

        #expect(question.hasPartnerAnswer)
        #expect(question.isAwaitingCurrentUserAnswer)
        #expect(question.canSubmitTextAnswer)
        #expect(!question.canViewPartnerAnswer)
        #expect(question.partnerAnswerDetail == nil)
    }

    @Test func bothAnsweredRevealedQuestionIncludesPartnerText() throws {
        let ownAnswerID = dailyFixedUUID("cccccccc-cccc-cccc-cccc-cccccccccccc")
        let partnerAnswerID = dailyFixedUUID("dddddddd-dddd-dddd-dddd-dddddddddddd")
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    ownAnswerID: ownAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate.addingTimeInterval(30),
                    partnerAnswerID: partnerAnswerID,
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                    canViewPartnerAnswer: true
                ),
            ],
            details: [
                dailyAnswerDetail(answerID: ownAnswerID, isOwnAnswer: true, textBody: "Tomorrow morning."),
                dailyAnswerDetail(
                    answerUserID: TestDailyChallengeIDs.partnerUser,
                    answerID: partnerAnswerID,
                    isOwnAnswer: false,
                    textBody: "A walk after school."
                ),
            ]
        )

        let question = try #require(snapshot.todayQuestion)

        #expect(question.hasOwnAnswer)
        #expect(question.canViewPartnerAnswer)
        #expect(question.partnerAnswerDetail?.canViewAnswer == true)
        #expect(question.partnerAnswerDetail?.textBody == "A walk after school.")
    }

    @Test func answeredQuestionRemainsResolvableAfterLeavingTheWaitingList() throws {
        let instanceID = UUID()
        let ownAnswerID = UUID()
        let partnerAnswerID = UUID()
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                instanceID: instanceID,
                ownAnswerID: ownAnswerID,
                ownAnsweredAt: TestDailyChallengeIDs.answerDate.addingTimeInterval(10),
                partnerAnswerID: partnerAnswerID,
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                canViewPartnerAnswer: true
            ),
        ])

        // The waiting list drops a question once this user answers it, but a presented
        // reveal must still resolve it by stable instance id.
        #expect(snapshot.questionsAwaitingAnswer.allSatisfy { $0.id != instanceID })
        let revealed = try #require(snapshot.questions.first { $0.id == instanceID })
        #expect(revealed.canViewPartnerAnswer)
    }

    @Test func answerKindMappingPreservesBackendKindsAndUnknowns() {
        #expect(DailyChallengeAnswerKind(rawValue: "text") == .text)
        #expect(DailyChallengeAnswerKind(rawValue: "photo") == .photo)
        #expect(DailyChallengeAnswerKind(rawValue: "voice") == .voice)
        #expect(DailyChallengeAnswerKind(rawValue: "partner_choice") == .partnerChoice)
        #expect(DailyChallengeAnswerKind(rawValue: "sticker") == .unknown("sticker"))
        #expect(DailyChallengeAnswerKind(rawValue: "voice").rawValue == "voice")
    }
}
