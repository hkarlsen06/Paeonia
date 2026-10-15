import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeEditingTests {
    @MainActor
    @Test func draftsSurviveReopenAndClearOnSubmit() async throws {
        let baseSnapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let store = InMemoryDailyChallengeDraftStore()
        let pendingStore = InMemoryPendingSyncOperationRepository()

        let first = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: store,
            pendingOperationStore: pendingStore
        )
        await first.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(first.snapshot.ownQuestions.first)
        first.setDraftText("Halfway through a thought", for: question.id)

        // Reopen / relaunch: a fresh view model restores the saved drafts.
        let second = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: store,
            pendingOperationStore: pendingStore
        )
        await second.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(second.draftText(for: question.id) == "Halfway through a thought")

        await second.submitAnswer(for: question)
        #expect(second.draftText(for: question.id).isEmpty)
        #expect(store.drafts(for: TestDailyChallengeIDs.currentUser).isEmpty)
    }

    @MainActor
    @Test func shuffleLimitSurfacesFriendlyNoticeAndKeepsQuestion() async throws {
        let baseSnapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                promptEN: "Original question"
            ),
        ])
        let service = RecordingDailyChallengeService(
            snapshots: [baseSnapshot],
            shuffleError: DailyChallengeShuffleLimitError()
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let original = try #require(viewModel.snapshot.ownQuestions.first)

        await viewModel.shuffle(original)

        #expect(viewModel.notice == .shuffleLimitReached)
        #expect(viewModel.snapshot.ownQuestions.first?.prompt == "Original question")
    }

    @MainActor
    @Test func shuffleIgnoresAlreadyAnsweredOwnQuestion() async throws {
        let answerID = UUID()
        let answeredSnapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [dailyAnswerDetail(answerID: answerID, isOwnAnswer: true, textBody: "Done already.")]
        )
        let service = RecordingDailyChallengeService(snapshots: [answeredSnapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let answered = try #require(viewModel.snapshot.ownQuestions.first)

        await viewModel.shuffle(answered)

        #expect(await service.shuffledSlots.isEmpty)
        #expect(viewModel.notice == nil)
    }

    @Test func ownTextAnswerIsEditableOnlyWhilePrivate() {
        let privateAnswerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: privateAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
                dailyQuestionRow(
                    slotNumber: 2,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: UUID(),
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                    partnerAnswerID: UUID(),
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                    canViewPartnerAnswer: true
                ),
                dailyQuestionRow(slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser),
            ],
            details: [dailyAnswerDetail(answerID: privateAnswerID, isOwnAnswer: true, textBody: "Private draft")]
        )

        let own = snapshot.ownQuestions

        #expect(own[0].canEditOwnAnswer)   // answered, partner hasn't seen it
        #expect(!own[1].canEditOwnAnswer)  // revealed once partner answered
        #expect(!own[2].canEditOwnAnswer)  // not answered yet
    }

    @MainActor
    @Test func editTextAnswerSavesNewText() async throws {
        let answerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [dailyAnswerDetail(answerID: answerID, isOwnAnswer: true, textBody: "Old answer")]
        )
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(question.canEditOwnAnswer)

        viewModel.setDraftText("New answer", for: question.id)
        await viewModel.editTextAnswer(for: question)

        #expect(await service.editedTexts == ["New answer"])
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func editAfterPartnerAnsweredSurfacesLockedNotice() async throws {
        let answerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [dailyAnswerDetail(answerID: answerID, isOwnAnswer: true, textBody: "Old answer")]
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
        viewModel.setDraftText("New answer", for: question.id)

        await viewModel.editTextAnswer(for: question)

        #expect(viewModel.notice == .editLocked)
    }
}
