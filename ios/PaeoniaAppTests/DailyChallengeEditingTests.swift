import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeEditingTests {
    @MainActor
    @Test func draftsSurviveReopenAndClearOnSubmit() async throws {
        let baseSnapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(),
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
        let question = try #require(first.snapshot.todayQuestion)
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
                dailyQuestionRow(),
            ]),
        ])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        var topicQuestion = try #require(viewModel.snapshot.todayQuestion)
        topicQuestion.topicKey = "would_you_rather"

        await viewModel.shuffle(topicQuestion)

        #expect(await service.shuffleCount == 0)
    }

    @MainActor
    @Test func shuffleIgnoresAQuestionEitherPartnerAnswered() async throws {
        let answerID = UUID()
        let ownAnswered = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [dailyAnswerDetail(answerID: answerID, isOwnAnswer: true, textBody: "Done already.")]
        )
        let partnerAnswered = makeDailySnapshot(rows: [
            dailyQuestionRow(
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])

        for snapshot in [ownAnswered, partnerAnswered] {
            let service = RecordingDailyChallengeService(snapshots: [snapshot])
            let viewModel = DailyChallengeViewModel(
                service: service,
                operationProvider: FixedDailyChallengeOperationProvider()
            )

            await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
            let answered = try #require(viewModel.snapshot.todayQuestion)

            await viewModel.shuffle(answered)

            #expect(await service.shuffleCount == 0)
            #expect(viewModel.notice == nil)
        }
    }

    @Test func ownTextAnswerIsEditableOnlyWhilePrivate() {
        let privateAnswerID = UUID()
        let snapshot = makeDailySnapshot(
            rows: [
                dailyQuestionRow(
                    ownAnswerID: privateAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
                dailyQuestionRow(
                    ownAnswerID: UUID(),
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                    partnerAnswerID: UUID(),
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                    canViewPartnerAnswer: true
                ),
                dailyQuestionRow(),
            ],
            details: [dailyAnswerDetail(answerID: privateAnswerID, isOwnAnswer: true, textBody: "Private draft")]
        )

        let own = snapshot.questions

        #expect(own[0].canEditOwnAnswer)   // answered, partner hasn't seen it
        #expect(!own[1].canEditOwnAnswer)  // revealed once partner answered
        #expect(!own[2].canEditOwnAnswer)  // not answered yet
    }
}
