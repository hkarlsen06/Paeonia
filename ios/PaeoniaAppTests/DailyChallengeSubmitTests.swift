import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeSubmitTests {
    @MainActor
    @Test func submitAnswerQueuesTrimmedTextForBackgroundSend() async throws {
        let baseSnapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = DailyChallengeViewModel(
            service: service, operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(), pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.todayQuestion)
        viewModel.setDraftText("  Thinking of you  ", for: question.id)

        await viewModel.submitAnswer(for: question)

        // Saved on the device and shown as sending right away — nothing was lost and no
        // error was raised — with the trimmed text queued for the sync engine to send.
        #expect(viewModel.isSending(question.id))
        // On its first try it is only sending, so no "saved on this phone" line.
        #expect(!viewModel.isHeldOnPhone(question.id))
        #expect(viewModel.notice == nil)
        #expect(viewModel.draftText(for: question.id).isEmpty)
        #expect(viewModel.sendingText(for: question.id) == "Thinking of you")

        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser, kind: .submitDailyAnswer
        )
        #expect(queued.count == 1)
        let data = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
        #expect(payload.instanceID == question.id)
        #expect(payload.content == .text("Thinking of you"))

        // The try fails. The answer is now held on this phone, and the screen says so.
        try await pendingStore.markRetryableFailure(
            clientOperationID: try #require(queued.first).operation.id,
            errorDescription: String(describing: URLError(.notConnectedToInternet)), nextRetryAt: nil, at: Date()
        )

        let relaunched = DailyChallengeViewModel(
            service: service, operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(), pendingOperationStore: pendingStore
        )
        await relaunched.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(relaunched.isSending(question.id))
        #expect(relaunched.isHeldOnPhone(question.id))
        #expect(relaunched.sendingText(for: question.id) == "Thinking of you")
    }

    @MainActor
    @Test func submitAnswerDoesNotWaitForSyncNudge() async throws {
        let baseSnapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let syncProbe = DailyChallengeSyncNudgeProbe()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            pendingOperationStore: pendingStore
        )
        viewModel.setLocalChangeSyncHandler {
            await syncProbe.blockUntilReleased()
        }

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.todayQuestion)
        viewModel.setDraftText(" Thinking of you ", for: question.id)

        let submitTask = Task { @MainActor in
            await viewModel.submitAnswer(for: question)
            await syncProbe.markSubmitReturned()
        }

        for _ in 0..<1_000 {
            if await syncProbe.didSubmitReturn() {
                break
            }
            await Task.yield()
        }

        #expect(await syncProbe.didSubmitReturn())
        #expect(viewModel.isSending(question.id))

        await syncProbe.release()
        await submitTask.value
    }
}
