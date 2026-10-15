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

    @MainActor
    @Test func editPartnerChoiceSavesNewSelection() async throws {
        let answerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [
                dailyAnswerDetail(
                    answerID: answerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(question.editableAnswerKind == .partnerChoice)

        // Switch the pick from the partner to "you", then save.
        viewModel.setPartnerChoice(TestDailyChallengeIDs.currentUser, for: question.id)
        await viewModel.editPartnerChoiceAnswer(for: question)

        #expect(await service.editedChoices == [TestDailyChallengeIDs.currentUser])
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func editPartnerChoiceAfterPartnerAnsweredSurfacesLockedNotice() async throws {
        let answerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [
                dailyAnswerDetail(
                    answerID: answerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )
        let service = RecordingDailyChallengeService(
            snapshots: [snapshot],
            editError: DailyChallengeEditLockedError()
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        viewModel.setPartnerChoice(TestDailyChallengeIDs.currentUser, for: question.id)

        await viewModel.editPartnerChoiceAnswer(for: question)

        #expect(viewModel.notice == .editLocked)
    }

    @Test func partnerChoiceOptionsCarryAvatarMetadata() throws {
        let currentPhoto = UUID()
        let partnerPhoto = UUID()
        let participants = DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            currentDisplayName: "Hjalmar",
            currentProfilePhotoAssetID: currentPhoto,
            partnerUserID: TestDailyChallengeIDs.partnerUser,
            partnerDisplayName: "Oda",
            partnerProfilePhotoAssetID: partnerPhoto
        )

        let options = try #require(participants.partnerChoiceOptions)
        // Current user keeps the "you" caption but uses their real name + photo for the avatar.
        #expect(options[0].label != "Hjalmar")
        #expect(options[0].avatarName == "Hjalmar")
        #expect(options[0].profilePhotoAssetID == currentPhoto)
        #expect(options[1].label == "Oda")
        #expect(options[1].avatarName == "Oda")
        #expect(options[1].profilePhotoAssetID == partnerPhoto)
    }

    @Test func partnerChoiceParticipantsResolveNamesAndOptions() throws {
        let participants = DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            partnerUserID: TestDailyChallengeIDs.partnerUser,
            partnerDisplayName: "Oda"
        )

        let options = try #require(participants.partnerChoiceOptions)
        #expect(options.count == 2)
        #expect(options[0].id == TestDailyChallengeIDs.currentUser)
        #expect(options[0].isCurrentUser)
        #expect(options[1].id == TestDailyChallengeIDs.partnerUser)
        #expect(options[1].label == "Oda")

        #expect(participants.name(for: TestDailyChallengeIDs.partnerUser) == "Oda")
        // The current user resolves to the localized "you" label, distinct from the partner.
        #expect(participants.name(for: TestDailyChallengeIDs.currentUser) != "Oda")
    }

    @Test func partnerChoiceOptionsHiddenWithoutPartnerIdentity() {
        let participants = DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            partnerUserID: nil,
            partnerDisplayName: nil
        )
        #expect(participants.partnerChoiceOptions == nil)
    }

    @Test func partnerChoiceAnswerExposesSelectedUserInDetail() throws {
        let answerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [
                dailyAnswerDetail(
                    answerID: answerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.hasOwnAnswer)
        #expect(question.ownAnswerDetail?.selectedUserID == TestDailyChallengeIDs.partnerUser)
    }

    @MainActor
    @Test func partnerChoiceDraftPersistsAcrossReopen() throws {
        let suiteName = "test.dailyChallenge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = TestDailyChallengeIDs.currentUser
        let instanceID = UUID()
        UserDefaultsDailyChallengeDraftStore(defaults: defaults)
            .setDraft(
                DailyAnswerDraft(partnerChoiceUserID: TestDailyChallengeIDs.partnerUser),
                for: instanceID,
                userID: userID
            )

        let reopened = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(reopened.drafts(for: userID)[instanceID]?.partnerChoiceUserID == TestDailyChallengeIDs.partnerUser)
    }
}
