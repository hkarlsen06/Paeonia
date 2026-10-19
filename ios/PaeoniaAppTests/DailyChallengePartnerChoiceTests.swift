import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengePartnerChoiceTests {
    @Test func partnerChoiceAnswerIsEditableWhilePrivateButNotAfterReveal() throws {
        let privateAnswerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: privateAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
                dailyQuestionRow(
                    slotNumber: 2,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: UUID(),
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                    partnerAnswerID: UUID(),
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                    canViewPartnerAnswer: true
                ),
            ],
            details: [
                dailyAnswerDetail(
                    answerID: privateAnswerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )

        let own = snapshot.ownQuestions
        #expect(own[0].editableAnswerKind == .partnerChoice)  // answered, still private
        #expect(own[0].canEditOwnAnswer)
        #expect(own[1].editableAnswerKind == nil)             // revealed once partner answered
        #expect(!own[1].canEditOwnAnswer)
    }

    private func choiceQuestion(
        ownSelection: UUID?, partnerSelection: UUID?, partnerCanView: Bool = true, ownText: String? = nil
    ) throws -> DailyChallengeQuestion {
        let ownAnswerID = UUID()
        let partnerAnswerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                    answerKinds: [.partnerChoice], ownAnswerID: ownAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate, partnerAnswerID: partnerAnswerID,
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate, canViewPartnerAnswer: partnerCanView
                ),
            ],
            details: [
                dailyAnswerDetail(
                    answerUserID: TestDailyChallengeIDs.currentUser, answerID: ownAnswerID, isOwnAnswer: true,
                    textBody: ownText, selectedUserID: ownSelection
                ),
                dailyAnswerDetail(
                    answerUserID: TestDailyChallengeIDs.partnerUser, answerID: partnerAnswerID, isOwnAnswer: false,
                    canViewAnswer: partnerCanView, selectedUserID: partnerSelection
                ),
            ]
        )
        return try #require(snapshot.ownQuestions.first)
    }

    @Test func sharedPartnerChoiceCollapsesOnlyWhenBothPickSamePersonWithNothingElse() throws {
        // Both picked the same person with nothing else: collapse into one shared row.
        #expect(
            try choiceQuestion(
                ownSelection: TestDailyChallengeIDs.partnerUser, partnerSelection: TestDailyChallengeIDs.partnerUser
            ).sharedPartnerChoiceUserID == TestDailyChallengeIDs.partnerUser
        )

        // Different picks stay as two separate rows.
        #expect(
            try choiceQuestion(
                ownSelection: TestDailyChallengeIDs.currentUser, partnerSelection: TestDailyChallengeIDs.partnerUser
            ).sharedPartnerChoiceUserID == nil
        )

        // Same pick but the partner's answer isn't viewable yet: nothing to merge.
        #expect(
            try choiceQuestion(
                ownSelection: TestDailyChallengeIDs.partnerUser, partnerSelection: TestDailyChallengeIDs.partnerUser,
                partnerCanView: false
            ).sharedPartnerChoiceUserID == nil
        )

        // Same pick but one side added a caption: the answers differ, so keep both.
        #expect(
            try choiceQuestion(
                ownSelection: TestDailyChallengeIDs.partnerUser, partnerSelection: TestDailyChallengeIDs.partnerUser,
                ownText: "Always you."
            ).sharedPartnerChoiceUserID == nil
        )
    }
}
