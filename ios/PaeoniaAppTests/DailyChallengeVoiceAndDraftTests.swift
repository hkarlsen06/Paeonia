import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeVoiceAndDraftTests {
    @MainActor
    @Test func stageVoiceQueuesVoiceAnswerForBackgroundSend() async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(answerKinds: [.voice]),
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
        let question = try #require(viewModel.snapshot.todayQuestion)
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
    @Test(arguments: ["text", "voice", "both"])
    func combinedVoiceAnswerKeepsEveryIncludedPart(parts: String) async throws {
        let snapshot = makeDailySnapshot(rows: [dailyQuestionRow(answerKinds: [.text, .voice])])
        let pending = InMemoryPendingSyncOperationRepository()
        let viewModel = DailyChallengeViewModel(
            service: RecordingDailyChallengeService(snapshots: [snapshot]),
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore(),
            pendingOperationStore: pending
        )
        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.todayQuestion)
        #expect(!viewModel.hasDraftToSubmit(for: question))
        if parts != "voice" { viewModel.setDraftText("The rain on the roof", for: question.id) }
        if parts != "text" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data([1, 2, 3, 4]).write(to: url)
            viewModel.stageVoice(url: url, durationMs: 4_200, for: question.id)
        }
        await viewModel.submitAnswer(for: question)
        let operations = try await pending.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser, kind: .submitDailyAnswer
        )
        let data = try #require(operations.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
        switch payload.content {
        case let .text(text):
            #expect(parts == "text")
            #expect(text == "The rain on the roof")
        case let .media(media):
            #expect(parts == "voice")
            #expect(media.draft.purpose == .voice)
            #expect(media.stagedData == Data([1, 2, 3, 4]))
        case let .textAndMedia(text, media):
            #expect(parts == "both")
            #expect(text == "The rain on the roof")
            #expect(media.draft.purpose == .voice)
            #expect(media.stagedData == Data([1, 2, 3, 4]))
        default:
            Issue.record("The queued answer lost its text or recording")
        }
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
