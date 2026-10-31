import Foundation
import Testing
@testable import PaeoniaApp

struct ThreadChatVoiceDraftTests {
    @MainActor
    @Test func restoredRecordingIsRemovedByThePrivacyPurge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = DailyVoiceRecorder(temporaryDirectory: directory)
        try recorder.restoreRecording(data: Data([1, 2, 3]), durationMs: 1_500)
        let recording = try #require(recorder.recordedURL)
        let unrelated = directory.appendingPathComponent("unrelated.txt")
        try Data([4]).write(to: unrelated)
        LiveLocalPrivateContentPurger.removeTemporaryVoiceFiles(in: directory)
        #expect(!FileManager.default.fileExists(atPath: recording.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func recordingAndTranscriptSurviveReopeningTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatVoiceDraftStore(directory: directory)
        let key = ThreadChatVoiceDraftKey(ownerUserID: UUID(), coupleID: UUID(), subject: .question(UUID()))
        let writerID = try #require(store.beginEditing(key, generation: store.generation))
        let draft = ThreadChatVoiceDraft(audio: Data([1, 2, 3]), durationMs: 1_500, transcript: "I miss you.")
        #expect(try store.save(draft, for: key, generation: store.generation, writerID: writerID))
        let reopened = FileThreadChatVoiceDraftStore(directory: directory)
        #expect(try reopened.read(key, generation: reopened.generation) == draft)
        let reopenedWriter = try #require(reopened.beginEditing(key, generation: reopened.generation))
        try reopened.remove(key, generation: reopened.generation, writerID: reopenedWriter)
        #expect(try reopened.read(key, generation: reopened.generation) == nil)
    }

    @Test func draftsDoNotCrossAccountsCouplesOrConversations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatVoiceDraftStore(directory: directory)
        let key = ThreadChatVoiceDraftKey(ownerUserID: UUID(), coupleID: UUID(), subject: .question(UUID()))
        let writerID = try #require(store.beginEditing(key, generation: store.generation))
        let draft = ThreadChatVoiceDraft(audio: Data([1]), durationMs: 1_000, transcript: "Private")
        try store.save(draft, for: key, generation: store.generation, writerID: writerID)
        for other in [
            ThreadChatVoiceDraftKey(ownerUserID: UUID(), coupleID: key.coupleID, subject: key.subject),
            ThreadChatVoiceDraftKey(ownerUserID: key.ownerUserID, coupleID: UUID(), subject: key.subject),
            ThreadChatVoiceDraftKey(
                ownerUserID: key.ownerUserID, coupleID: key.coupleID, subject: .memory(key.subject.id)
            )
        ] {
            #expect(try store.read(other, generation: store.generation) == nil)
        }
    }

    @Test func disappearingComposerCannotRecreateARecordingAfterPrivacyPurge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatVoiceDraftStore(directory: directory)
        let key = ThreadChatVoiceDraftKey(ownerUserID: UUID(), coupleID: UUID(), subject: .story(UUID()))
        let writerID = try #require(store.beginEditing(key, generation: store.generation))
        let draft = ThreadChatVoiceDraft(audio: Data([1]), durationMs: 1_000, transcript: "Private")
        let composerGeneration = store.generation
        try store.save(draft, for: key, generation: composerGeneration, writerID: writerID)
        store.clearAll()
        #expect(try !store.save(draft, for: key, generation: composerGeneration, writerID: writerID))
        #expect(try store.read(key, generation: store.generation) == nil)
        let newWriter = try #require(store.beginEditing(key, generation: store.generation))
        #expect(try store.save(draft, for: key, generation: store.generation, writerID: newWriter))
    }

    @MainActor
    @Test func aCompletedOldSendCannotDiscardAReopenedComposersNewRecording() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatVoiceDraftStore(directory: directory)
        let fixture = ChatTestFixture()
        let viewModel = ThreadChatViewModel(
            subject: .question(fixture.question.questionID), coupleID: fixture.question.coupleID,
            participants: DailyChallengeParticipants(
                currentUserID: fixture.ownerUserID, currentDisplayName: "You",
                partnerUserID: fixture.partnerUserID, partnerDisplayName: "Partner"
            ),
            service: fixture.makeService(), voiceDraftStore: store
        )
        let oldEditing = try #require(viewModel.beginVoiceDraftEditing())
        let earlier = ThreadChatVoiceDraft(audio: Data([1]), durationMs: 1_000, transcript: "Earlier")
        #expect(oldEditing.save(earlier))
        let newEditing = try #require(viewModel.beginVoiceDraftEditing())
        let latest = ThreadChatVoiceDraft(audio: Data([2]), durationMs: 2_000, transcript: "Latest")
        #expect(newEditing.save(latest))
        oldEditing.discard()
        #expect(!oldEditing.save(earlier))
        #expect(viewModel.beginVoiceDraftEditing()?.draft == latest)
    }
}
