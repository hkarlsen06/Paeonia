import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct ThreadChatPhotoDraftTests {
    @Test func photosDescriptionsAndCaptionSurviveComposerAndStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = ChatTestFixture()
        let first = makeViewModel(fixture, store: FileThreadChatPhotoDraftStore(directory: directory))
        let editing = try #require(first.beginPhotoDraftEditing())
        let staging = ThreadChatPhotoStaging()
        staging.onDraftChange = { _ = editing.save($0) }
        staging.restore(ThreadChatPhotoDraft(photos: photos(), caption: "The weekend"))
        staging.updateCaption("Our weekend by the sea")
        let photoID = try #require(staging.staged.first?.id)
        staging.setDescription("Our red boat beside the old dock", for: photoID)

        let reopened = makeViewModel(fixture, store: FileThreadChatPhotoDraftStore(directory: directory))
        let restored = try #require(reopened.beginPhotoDraftEditing()?.draft)
        let recreated = ThreadChatPhotoStaging()
        recreated.restore(restored)
        #expect(restored.caption == "Our weekend by the sea")
        #expect(recreated.photos.map(\.data) == [Data([1, 2]), Data([3, 4])])
        #expect(recreated.photos.map(\.accessibilityText) == [
            "Our red boat beside the old dock", "The old dock",
        ])
        // Restored copies remain selected when the library's new selection starts empty.
        recreated.pickerItems = []
        #expect(recreated.photos == restored.photos)
    }

    @Test func aPurgeRejectsLatePhotoChangesAndStaleDiscarding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatPhotoDraftStore(directory: directory)
        let fixture = ChatTestFixture()
        let oldComposer = makeViewModel(fixture, store: store)
        let oldEditing = try #require(oldComposer.beginPhotoDraftEditing())
        let draft = ThreadChatPhotoDraft(photos: photos(), caption: "Private")
        #expect(oldEditing.save(draft))
        store.clearAll()
        #expect(!oldEditing.save(draft))

        let newComposer = makeViewModel(fixture, store: store)
        let newEditing = try #require(newComposer.beginPhotoDraftEditing())
        #expect(newEditing.draft == nil)
        #expect(newEditing.save(draft))
        _ = oldEditing.save(ThreadChatPhotoDraft(photos: [], caption: ""))
        #expect(newComposer.beginPhotoDraftEditing()?.draft == draft)
    }

    @Test func draftsArePrivateToTheirOwnerCoupleAndConversation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatPhotoDraftStore(directory: directory)
        let key = ThreadChatPhotoDraftKey(ownerUserID: UUID(), coupleID: UUID(), subject: .question(UUID()))
        let draft = ThreadChatPhotoDraft(photos: photos(), caption: "Private")
        let writerID = try #require(store.beginEditing(key, generation: store.generation))
        try store.save(draft, for: key, generation: store.generation, writerID: writerID)
        for other in [
            ThreadChatPhotoDraftKey(ownerUserID: UUID(), coupleID: key.coupleID, subject: key.subject),
            ThreadChatPhotoDraftKey(ownerUserID: key.ownerUserID, coupleID: UUID(), subject: key.subject),
            ThreadChatPhotoDraftKey(
                ownerUserID: key.ownerUserID, coupleID: key.coupleID, subject: .memory(key.subject.id)
            ),
        ] {
            #expect(try store.read(other, generation: store.generation) == nil)
        }
    }

    @Test func successfulSendingKeepsADescriptionEditedDuringTheSend() throws {
        let staging = ThreadChatPhotoStaging()
        staging.restore(ThreadChatPhotoDraft(photos: photos(), caption: "Look"))
        let sent = staging.staged
        let keptID = try #require(sent.first?.id)
        staging.setDescription("A clearer description I wrote during sending", for: keptID)
        staging.removeSent(sent)
        #expect(staging.staged.map(\.id) == [keptID])
        #expect(staging.photos.first?.accessibilityText == "A clearer description I wrote during sending")
    }

    @Test func aRefusedPhotoSendKeepsTheDraftForReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = ChatTestFixture()
        let viewModel = makeViewModel(fixture, store: FileThreadChatPhotoDraftStore(directory: directory))
        let editing = try #require(viewModel.beginPhotoDraftEditing())
        var selected = photos()
        selected[0].accessibilityText = String(repeating: "x", count: 10_001)
        let draft = ThreadChatPhotoDraft(photos: selected, caption: "I still need to edit the description")
        #expect(editing.save(draft))
        #expect(!(await viewModel.send(draft.caption, photos: draft.photos)))
        let reopened = makeViewModel(fixture, store: FileThreadChatPhotoDraftStore(directory: directory))
        #expect(reopened.beginPhotoDraftEditing()?.draft == draft)
    }

    @Test func aLateSuccessfulSendCannotEraseAReopenedComposersNewDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatPhotoDraftStore(directory: directory)
        let viewModel = makeViewModel(ChatTestFixture(), store: store)
        let oldEditing = try #require(viewModel.beginPhotoDraftEditing())
        let oldDraft = ThreadChatPhotoDraft(photos: photos(), caption: "Earlier")
        #expect(oldEditing.save(oldDraft))
        let newEditing = try #require(viewModel.beginPhotoDraftEditing())
        let newDraft = ThreadChatPhotoDraft(photos: [photos()[1]], caption: "A new caption")
        #expect(newEditing.save(newDraft))
        _ = oldEditing.save(ThreadChatPhotoDraft(photos: [], caption: ""))
        #expect(!oldEditing.save(oldDraft))
        #expect(viewModel.beginPhotoDraftEditing()?.draft == newDraft)
    }

    @Test func aPhotoFinishingAfterDismissalStillPersistsUnlessTheComposerWasReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = ChatTestFixture()
        let store = FileThreadChatPhotoDraftStore(directory: directory)
        let staging = ThreadChatPhotoStaging()
        do {
            let viewModel = makeViewModel(fixture, store: store)
            let editing = try #require(viewModel.beginPhotoDraftEditing())
            staging.onDraftChange = { _ = editing.save($0) }
        }
        let draft = ThreadChatPhotoDraft(photos: photos(), caption: "Picked before leaving")
        staging.restore(draft)
        let reopened = makeViewModel(fixture, store: FileThreadChatPhotoDraftStore(directory: directory))
        #expect(reopened.beginPhotoDraftEditing()?.draft == draft)
    }

    private func photos() -> [ThreadChatPhoto] {
        [
            ThreadChatPhoto(data: Data([1, 2]), width: 400, height: 300, accessibilityText: "The red boat"),
            ThreadChatPhoto(data: Data([3, 4]), width: 300, height: 400, accessibilityText: "The old dock"),
        ]
    }

    private func makeViewModel(
        _ fixture: ChatTestFixture, store: FileThreadChatPhotoDraftStore
    ) -> ThreadChatViewModel {
        ThreadChatViewModel(
            subject: .question(fixture.question.questionID), coupleID: fixture.question.coupleID,
            question: fixture.question,
            participants: DailyChallengeParticipants(
                currentUserID: fixture.ownerUserID, currentDisplayName: "You",
                partnerUserID: fixture.partnerUserID, partnerDisplayName: "Partner"
            ),
            service: fixture.makeService(), operationProvider: fixture.operationProvider,
            photoDraftStore: store
        )
    }
}
