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
        // Typed text reaches the store after a short pause, or when the screen closes.
        #expect(store.drafts(for: TestDailyChallengeIDs.currentUser).isEmpty)
        first.flushDraftPersistence()

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
    @Test func shuffleNeverSwapsATopicQuestion() async throws {
        let service = RecordingDailyChallengeService(snapshots: [
            makeDailySnapshot(rows: [
                dailyQuestionRow(slotNumber: 0, seededForUserID: TestDailyChallengeIDs.currentUser),
            ]),
        ])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        var topicQuestion = try #require(viewModel.snapshot.ownQuestions.first)
        topicQuestion.topicKey = "would_you_rather"

        await viewModel.shuffle(topicQuestion)

        #expect(await service.shuffledSlots.isEmpty)
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
}
