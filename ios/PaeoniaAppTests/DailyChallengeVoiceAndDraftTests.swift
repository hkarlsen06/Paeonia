import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeVoiceAndDraftTests {
    @Test func voiceQuestionIsComposableAndRevealsAsVoice() throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.voice]
            ),
        ])

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.composableAnswerKinds == [.voice])
        #expect(question.defaultComposableKind == .voice)
        #expect(question.mediaAnswerKind == .voice)
        #expect(question.canSubmitAnswer)
    }

    @Test func photoQuestionRevealsAsPhoto() throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.mediaAnswerKind == .photo)
    }

    @MainActor
    @Test func stageVoiceQueuesVoiceAnswerForBackgroundSend() async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, answerKinds: [.voice]),
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
        #expect(viewModel.composeKind(for: question) == .voice)
        #expect(!viewModel.hasDraftToSubmit(for: question))

        let voiceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-voice-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: voiceURL)
        viewModel.stageVoice(url: voiceURL, durationMs: 4_200, for: question.id)

        #expect(viewModel.hasDraftToSubmit(for: question))
        #expect(viewModel.stagedVoiceDurationMs(for: question.id) == 4_200)

        await viewModel.submitAnswer(for: question)

        #expect(viewModel.isSending(question.id))
        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser, kind: .submitDailyAnswer
        )
        #expect(queued.count == 1)

        let data = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
        guard case let .media(media) = payload.content else {
            Issue.record("Expected media content, got \(payload.content)")
            return
        }
        #expect(media.draft.purpose == .voice)
        #expect(media.draft.durationMs == 4_200)
        #expect(media.stagedData == Data([0x00, 0x01, 0x02, 0x03]))
    }

    @MainActor
    @Test func sendingVoiceNoteStaysPlayableWithDurationAfterDraftCleared() async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.voice]
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

        let voiceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-voice-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: voiceURL)
        viewModel.stageVoice(url: voiceURL, durationMs: 4_200, for: question.id)

        await viewModel.submitAnswer(for: question)

        // The editable draft is gone once it's queued, but the sending preview still
        // has the bytes and the recorded length so it stays playable on both screens.
        #expect(viewModel.isSending(question.id))
        #expect(viewModel.stagedVoiceDurationMs(for: question.id) == nil)
        #expect(viewModel.sendingMediaData(for: question.id) != nil)
        #expect(viewModel.sendingVoiceDurationMs(for: question.id) == 4_200)

        let relaunched = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore(),
            pendingOperationStore: pendingStore
        )
        await relaunched.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(relaunched.isSending(question.id))
        #expect(relaunched.stagedVoiceDurationMs(for: question.id) == nil)
        #expect(relaunched.sendingMediaData(for: question.id) != nil)
        #expect(relaunched.sendingVoiceDurationMs(for: question.id) == 4_200)
    }

    @Test func stagedMediaDraftStoreRoundTripsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dailyChallengeMediaTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileDailyAnswerMediaDraftStore(directoryURL: directory)
        let instanceID = UUID()
        let data = Data([0x01, 0x02, 0x03, 0x04])

        try store.writeStagedMedia(data, instanceID: instanceID)
        #expect(store.stagedMediaData(instanceID: instanceID) == data)
        let reopened = FileDailyAnswerMediaDraftStore(directoryURL: directory)
        #expect(reopened.stagedMediaData(instanceID: instanceID) == data)

        store.removeStagedMedia(instanceID: instanceID)
        #expect(store.stagedMediaData(instanceID: instanceID) == nil)

        try store.writeStagedMedia(data, instanceID: instanceID)
        store.clearAll()
        #expect(store.stagedMediaData(instanceID: instanceID) == nil)
    }

    @MainActor
    @Test func mediaDraftPersistsAcrossReopen() throws {
        let suiteName = "test.dailyChallenge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = TestDailyChallengeIDs.currentUser
        let instanceID = UUID()
        let media = DailyAnswerMediaDraft(
            purpose: .photo,
            mimeType: "image/jpeg",
            fileExtension: "jpg",
            width: 100,
            height: 80,
            durationMs: nil
        )

        UserDefaultsDailyChallengeDraftStore(defaults: defaults)
            .setDraft(DailyAnswerDraft(media: media), for: instanceID, userID: userID)

        let reopened = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(reopened.drafts(for: userID)[instanceID]?.media == media)
    }

    @MainActor
    @Test func draftStoreRoundTripsAndClears() throws {
        let suiteName = "test.dailyChallenge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = TestDailyChallengeIDs.currentUser
        let instanceID = UUID()

        UserDefaultsDailyChallengeDraftStore(defaults: defaults)
            .setDraft(DailyAnswerDraft(text: "Saved across launches"), for: instanceID, userID: userID)

        let reopened = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(reopened.drafts(for: userID)[instanceID]?.text == "Saved across launches")

        reopened.clearDraft(for: instanceID, userID: userID)
        #expect(UserDefaultsDailyChallengeDraftStore(defaults: defaults).drafts(for: userID).isEmpty)
    }
}
