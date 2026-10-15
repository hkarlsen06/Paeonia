import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengePhotoAnswerTests {
    @Test func photoCapableQuestionDefaultsToTextAndExposesBothKinds() throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.composableAnswerKinds == [.photo, .text])
        #expect(question.defaultComposableKind == .text)
        #expect(question.canSubmitAnswer)
    }

    @MainActor
    @Test func submitPhotoAnswerQueuesForBackgroundSendAndMarksSending() async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, answerKinds: [.photo, .text]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = DailyChallengeViewModel(
            service: service, operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(), mediaDraftStore: mediaStore,
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)

        // A two-kind question opens on text and isn't sendable until a photo is staged.
        #expect(viewModel.composeKind(for: question) == .text)
        viewModel.setComposeKind(.photo, for: question.id)
        #expect(viewModel.composeKind(for: question) == .photo)
        #expect(!viewModel.hasDraftToSubmit(for: question))

        await viewModel.stagePhoto(dailySampleImageData(), for: question.id)
        #expect(viewModel.hasDraftToSubmit(for: question))

        await viewModel.submitAnswer(for: question)

        // Queued for background send, shown as sending, with the staged bytes kept so
        // the upload can finish.
        #expect(viewModel.isSending(question.id))
        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser, kind: .submitDailyAnswer
        )
        #expect(queued.count == 1)
        let queuedData = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: queuedData)
        guard case let .media(media) = payload.content else {
            Issue.record("Expected media content, got \(payload.content)")
            return
        }
        #expect(media.stagedData != nil)
        #expect(viewModel.sendingMediaData(for: question.id) != nil)
        // A photo-only answer has no caption text or partner pick.
        #expect(viewModel.sendingText(for: question.id) == nil)

        await expectPhotoStillSendingAfterRelaunch(service, pendingStore, questionID: question.id)
    }

    /// A fresh view model, like a relaunch, still shows the queued photo answer as sending.
    @MainActor
    private func expectPhotoStillSendingAfterRelaunch(
        _ service: RecordingDailyChallengeService,
        _ pendingStore: InMemoryPendingSyncOperationRepository,
        questionID: UUID
    ) async {
        let relaunched = DailyChallengeViewModel(
            service: service, operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(), mediaDraftStore: InMemoryDailyAnswerMediaDraftStore(),
            pendingOperationStore: pendingStore
        )
        await relaunched.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(relaunched.isSending(questionID))
        #expect(relaunched.sendingMediaData(for: questionID) != nil)
        #expect(relaunched.sendingText(for: questionID) == nil)
    }

    @Test func combinedComposeAppliesOnlyToTextWithPhotoOrPartnerChoice() {
        func secondaryKind(_ kinds: [DailyChallengeAnswerKind]) -> DailyChallengeAnswerKind? {
            makeDailySnapshot(rows: [
                dailyQuestionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, answerKinds: kinds)
            ]).ownQuestions[0].combinedSecondaryKind
        }

        #expect(secondaryKind([.text, .photo]) == .photo)
        #expect(secondaryKind([.photo, .text]) == .photo)
        #expect(secondaryKind([.text, .partnerChoice]) == .partnerChoice)
        #expect(secondaryKind([.text]) == nil)
        #expect(secondaryKind([.photo]) == nil)
        #expect(secondaryKind([.text, .voice]) == nil)
    }

    @Test func combinedAnswersAreNotEditable() {
        let combined = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                answerKinds: [.photo, .text],
                ownAnswerID: UUID()
            ),
        ]).ownQuestions[0]
        #expect(combined.usesCombinedCompose)
        #expect(combined.editableAnswerKind == nil)

        // A plain text answer is still editable while it's private.
        let textOnly = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                answerKinds: [.text],
                ownAnswerID: UUID()
            ),
        ]).ownQuestions[0]
        #expect(textOnly.editableAnswerKind == .text)
    }

    @MainActor
    @Test func submitCombinedPhotoAndTextQueuesBothTogether() async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: mediaStore,
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(question.usesCombinedCompose)

        // The user adds both a photo and a caption; either alone would also send.
        viewModel.setDraftText("By the lake", for: question.id)
        await viewModel.stagePhoto(dailySampleImageData(), for: question.id)
        #expect(viewModel.hasDraftToSubmit(for: question))

        await viewModel.submitAnswer(for: question)

        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser,
            kind: .submitDailyAnswer
        )
        let queuedData = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: queuedData)
        guard case let .textAndMedia(body, media) = payload.content else {
            Issue.record("Expected combined text+media content, got \(payload.content)")
            return
        }
        #expect(body == "By the lake")
        #expect(media.stagedData != nil)

        // Both parts stay visible in the "saved, sending" preview while it uploads.
        #expect(viewModel.sendingText(for: question.id) == "By the lake")
        #expect(viewModel.sendingMediaData(for: question.id) != nil)
    }
}
