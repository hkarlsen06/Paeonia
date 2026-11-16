import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct ThreadChatAttachmentDraftTests {
    @Test func photosDescriptionsAndCaptionSurviveComposerAndStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = ChatTestFixture()
        let first = makeViewModel(fixture, store: FileThreadChatAttachmentDraftStore(directory: directory))
        let editing = try #require(first.beginAttachmentDraftEditing())
        let staging = ThreadChatAttachmentStaging()
        staging.onDraftChange = { _ = editing.save($0) }
        staging.restore(ThreadChatAttachmentDraft(attachments: attachments(), caption: "The weekend"))
        staging.updateCaption("Our weekend by the sea")
        let photoID = try #require(staging.staged.first?.id)
        staging.setDescription("Our red boat beside the old dock", for: photoID)

        let reopened = makeViewModel(fixture, store: FileThreadChatAttachmentDraftStore(directory: directory))
        let restored = try #require(reopened.beginAttachmentDraftEditing()?.draft)
        let recreated = ThreadChatAttachmentStaging()
        recreated.restore(restored)
        #expect(restored.caption == "Our weekend by the sea")
        #expect(recreated.attachments.map(\.localBytes) == [Data([1, 2]), Data([3, 4])])
        #expect(recreated.attachments.map(\.accessibilityText) == [
            "Our red boat beside the old dock", "The old dock",
        ])
        // Restored copies remain selected when the library's new selection starts empty.
        recreated.pickerItems = []
        #expect(recreated.attachments == restored.attachments)
    }

    @Test func aPurgeRejectsLatePhotoChangesAndStaleDiscarding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatAttachmentDraftStore(directory: directory)
        let fixture = ChatTestFixture()
        let oldComposer = makeViewModel(fixture, store: store)
        let oldEditing = try #require(oldComposer.beginAttachmentDraftEditing())
        let draft = ThreadChatAttachmentDraft(attachments: attachments(), caption: "Private")
        #expect(oldEditing.save(draft))
        store.clearAll()
        #expect(!oldEditing.save(draft))

        let newComposer = makeViewModel(fixture, store: store)
        let newEditing = try #require(newComposer.beginAttachmentDraftEditing())
        #expect(newEditing.draft == nil)
        #expect(newEditing.save(draft))
        _ = oldEditing.save(ThreadChatAttachmentDraft(attachments: [], caption: ""))
        #expect(newComposer.beginAttachmentDraftEditing()?.draft == draft)
    }

    @Test func draftsArePrivateToTheirOwnerCoupleAndConversation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatAttachmentDraftStore(directory: directory)
        let key = ThreadChatAttachmentDraftKey(ownerUserID: UUID(), coupleID: UUID(), subject: .question(UUID()))
        let draft = ThreadChatAttachmentDraft(attachments: attachments(), caption: "Private")
        let writerID = try #require(store.beginEditing(key, generation: store.generation))
        try store.save(draft, for: key, generation: store.generation, writerID: writerID)
        for other in [
            ThreadChatAttachmentDraftKey(ownerUserID: UUID(), coupleID: key.coupleID, subject: key.subject),
            ThreadChatAttachmentDraftKey(ownerUserID: key.ownerUserID, coupleID: UUID(), subject: key.subject),
            ThreadChatAttachmentDraftKey(
                ownerUserID: key.ownerUserID, coupleID: key.coupleID, subject: .memory(key.subject.id)
            ),
        ] {
            #expect(try store.read(other, generation: store.generation) == nil)
        }
    }

    @Test func successfulSendingKeepsADescriptionEditedDuringTheSend() throws {
        let staging = ThreadChatAttachmentStaging()
        staging.restore(ThreadChatAttachmentDraft(attachments: attachments(), caption: "Look"))
        let sent = staging.staged
        let keptID = try #require(sent.first?.id)
        staging.setDescription("A clearer description I wrote during sending", for: keptID)
        staging.removeSent(sent)
        #expect(staging.staged.map(\.id) == [keptID])
        #expect(staging.attachments.first?.accessibilityText == "A clearer description I wrote during sending")
    }

    @Test func aRefusedPhotoSendKeepsTheDraftForReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = ChatTestFixture()
        let viewModel = makeViewModel(fixture, store: FileThreadChatAttachmentDraftStore(directory: directory))
        let editing = try #require(viewModel.beginAttachmentDraftEditing())
        var selected = attachments()
        selected[0].accessibilityText = String(repeating: "x", count: 10_001)
        let draft = ThreadChatAttachmentDraft(attachments: selected, caption: "I still need to edit the description")
        #expect(editing.save(draft))
        #expect(!(await viewModel.send(draft.caption, attachments: draft.attachments)))
        let reopened = makeViewModel(fixture, store: FileThreadChatAttachmentDraftStore(directory: directory))
        #expect(reopened.beginAttachmentDraftEditing()?.draft == draft)
    }

    @Test func aLateSuccessfulSendCannotEraseAReopenedComposersNewDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileThreadChatAttachmentDraftStore(directory: directory)
        let viewModel = makeViewModel(ChatTestFixture(), store: store)
        let oldEditing = try #require(viewModel.beginAttachmentDraftEditing())
        let oldDraft = ThreadChatAttachmentDraft(attachments: attachments(), caption: "Earlier")
        #expect(oldEditing.save(oldDraft))
        let newEditing = try #require(viewModel.beginAttachmentDraftEditing())
        let newDraft = ThreadChatAttachmentDraft(attachments: [attachments()[1]], caption: "A new caption")
        #expect(newEditing.save(newDraft))
        _ = oldEditing.save(ThreadChatAttachmentDraft(attachments: [], caption: ""))
        #expect(!oldEditing.save(oldDraft))
        #expect(viewModel.beginAttachmentDraftEditing()?.draft == newDraft)
    }

    @Test func aPhotoFinishingAfterDismissalStillPersistsUnlessTheComposerWasReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = ChatTestFixture()
        let store = FileThreadChatAttachmentDraftStore(directory: directory)
        let staging = ThreadChatAttachmentStaging()
        do {
            let viewModel = makeViewModel(fixture, store: store)
            let editing = try #require(viewModel.beginAttachmentDraftEditing())
            staging.onDraftChange = { _ = editing.save($0) }
        }
        let draft = ThreadChatAttachmentDraft(attachments: attachments(), caption: "Picked before leaving")
        staging.restore(draft)
        let reopened = makeViewModel(fixture, store: FileThreadChatAttachmentDraftStore(directory: directory))
        #expect(reopened.beginAttachmentDraftEditing()?.draft == draft)
    }

    private func attachments() -> [ThreadChatAttachment] {
        [
            ThreadChatAttachment(
                kind: .photo, local: .bytes(Data([1, 2])), width: 400, height: 300, accessibilityText: "The red boat"
            ),
            ThreadChatAttachment(
                kind: .photo, local: .bytes(Data([3, 4])), width: 300, height: 400, accessibilityText: "The old dock"
            ),
        ]
    }

    private func makeViewModel(
        _ fixture: ChatTestFixture, store: FileThreadChatAttachmentDraftStore
    ) -> ThreadChatViewModel {
        ThreadChatViewModel(
            subject: .question(fixture.question.questionID), coupleID: fixture.question.coupleID,
            question: fixture.question,
            participants: DailyChallengeParticipants(
                currentUserID: fixture.ownerUserID, currentDisplayName: "You",
                partnerUserID: fixture.partnerUserID, partnerDisplayName: "Partner"
            ),
            service: fixture.makeService(), operationProvider: fixture.operationProvider,
            attachmentDraftStore: store
        )
    }
}
