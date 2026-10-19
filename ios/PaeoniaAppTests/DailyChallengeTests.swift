import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeMappingTests {
    @Test func completedDayFollowUpDependsOnThePartner() {
        func state(partnerAnswered: Bool, answerable: Bool) -> DailyChallengeCardState {
            DailyChallengeCardState(
                kind: .complete,
                answeredCount: 2,
                totalCount: 2,
                hasPartnerAnswersForToday: partnerAnswered,
                hasAnswerablePartnerQuestions: answerable
            )
        }

        // Open partner questions come first, even when the partner also answered today.
        #expect(state(partnerAnswered: true, answerable: true).completeFollowUp == .partnerQuestionsToAnswer)
        #expect(state(partnerAnswered: false, answerable: false).completeFollowUp == .waitingForPartner)
        #expect(state(partnerAnswered: true, answerable: false).completeFollowUp == .bothAnswered)
    }

    @Test func partnerAnsweredUnrevealedQuestionCanBeAnsweredButBodyStaysHidden() throws {
        let partnerAnswerID = dailyFixedUUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                answerKinds: [.voice, .text],
                partnerAnswerID: partnerAnswerID,
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                canViewPartnerAnswer: false
            ),
        ])

        let question = try #require(snapshot.partnerStartedQuestions.first)

        #expect(question.origin == .partner)
        #expect(question.hasPartnerAnswer)
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
                    slotNumber: 2,
                    seededForUserID: TestDailyChallengeIDs.partnerUser,
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

        let question = try #require(snapshot.partnerStartedQuestions.first)

        #expect(question.hasOwnAnswer)
        #expect(question.canViewPartnerAnswer)
        #expect(question.partnerAnswerDetail?.canViewAnswer == true)
        #expect(question.partnerAnswerDetail?.textBody == "A walk after school.")
    }

    @Test func answeredPartnerQuestionRemainsResolvableAfterLeavingAnswerFlowOrder() throws {
        let instanceID = UUID()
        let ownAnswerID = UUID()
        let partnerAnswerID = UUID()
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                instanceID: instanceID,
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                status: "answered",
                ownAnswerID: ownAnswerID,
                ownAnsweredAt: TestDailyChallengeIDs.answerDate.addingTimeInterval(10),
                partnerAnswerID: partnerAnswerID,
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                canViewPartnerAnswer: true
            ),
        ])

        // Answer-flow ordering intentionally drops a partner question after this user
        // answers it, but a presented reveal must still resolve it by stable instance id.
        #expect(snapshot.answerFlowQuestions.allSatisfy { $0.id != instanceID })
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

    @Test func challengeProgressUsesOnlyCurrentUsersTwoSeededQuestions() {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            dailyQuestionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            dailyQuestionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])

        #expect(snapshot.visibleQuestions.count == 4)
        #expect(snapshot.progress.ownQuestionCount == 2)
        #expect(snapshot.progress.ownAnsweredCount == 2)
        #expect(snapshot.progress.partnerQuestionCount == 2)
        #expect(snapshot.progress.isComplete)
        #expect(snapshot.hasPartnerAnswersForToday)
        #expect(snapshot.homeCardState.hasPartnerAnswersForToday)
        #expect(snapshot.hasAnswerablePartnerQuestions)
        #expect(snapshot.answerablePartnerQuestions.count == 2)
        #expect(snapshot.answerFlowQuestions.count == 4)
    }
}
