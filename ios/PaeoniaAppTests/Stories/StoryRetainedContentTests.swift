import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct StoryRetainedContentTests {
    private let header = ThreadChatHeader(eyebrow: "Story", title: "", detail: nil, photoAssetID: nil)

    private func story() -> Story {
        Story(id: UUID(), authorUserID: UUID(), mediaAssetID: UUID(), caption: nil, createdAt: .now, seenAt: nil)
    }

    private func context(fixture: ChatTestFixture, store: RetainedContentPendingStore) -> ThreadChatContext {
        ThreadChatContext(
            coupleID: fixture.question.coupleID,
            participants: DailyChallengeParticipants(
                currentUserID: fixture.ownerUserID, currentDisplayName: "You",
                partnerUserID: fixture.partnerUserID, partnerDisplayName: "Robin"
            ),
            service: ThreadChatService(gateway: fixture.gateway, cache: fixture.cache, pendingOperationStore: store),
            operationProvider: fixture.operationProvider
        )
    }

    @Test func storyNavigationAndViewerReopeningKeepSeparateDraftsUntilPrivacyChanges() async {
        let fixture = ChatTestFixture()
        let context = context(fixture: fixture, store: RetainedContentPendingStore())
        let model = StoriesViewModel(cache: InMemoryStoriesCache(), gateway: FakeStoriesGateway())
        await model.configure(ownerUserID: fixture.ownerUserID, coupleID: fixture.question.coupleID)
        let first = story()
        let second = story()
        await model.replies.load(for: first, header: header, context: context)
        model.replies.draft = "First reply"
        #expect(model.replies.hasUnsentReply)
        await model.replies.load(for: second, header: header, context: context)
        #expect(model.replies.draft.isEmpty)
        model.replies.draft = "Second reply"
        await model.replies.load(for: first, header: header, context: context)
        #expect(model.replies.draft == "First reply")
        model.updateCoupleID(UUID())
        await model.replies.load(for: first, header: header, context: context)
        #expect(model.replies.draft.isEmpty)
    }

    @Test func successfulReplyKeepsTypingAcceptedWhileTheLocalWriteWasHeld() async throws {
        let fixture = ChatTestFixture()
        let store = RetainedContentPendingStore()
        let context = context(fixture: fixture, store: store)
        let replies = StoryReplies()
        let first = story()
        await replies.load(for: first, header: header, context: context)
        replies.draft = "Submitted reply"
        await store.holdNext()
        let sending = Task { await replies.send() }
        #expect(await waitUntil { await store.isHeld })
        replies.draft = "Submitted reply and a later thought"
        await store.resume()
        #expect(await sending.value)
        #expect(replies.draft == "Submitted reply and a later thought")
        #expect(!replies.justSent)
        #expect(replies.hasUnsentReply)
        await replies.load(for: story(), header: header, context: context)
        await replies.load(for: first, header: header, context: context)
        #expect(replies.draft == "Submitted reply and a later thought")
        let queued = await fixture.cache.messages(ownerUserID: fixture.ownerUserID, subjectID: first.id)
        #expect(queued.map(\.body) == ["Submitted reply"])
    }

    @Test func failedReplyKeepsItsTextAndSuccessfulRetryClearsOnlyThatVersion() async {
        let fixture = ChatTestFixture()
        let store = RetainedContentPendingStore()
        await store.fail(at: 1)
        let replies = StoryReplies()
        await replies.load(for: story(), header: header, context: context(fixture: fixture, store: store))
        replies.draft = "Please keep this"
        #expect(await !replies.send())
        #expect(replies.draft == "Please keep this")
        #expect(await replies.send())
        #expect(replies.draft.isEmpty)
    }

    @Test func aNoteSavedDuringNewTypingKeepsTheEditorOpenAndTheNewTextRetryable() async {
        let gateway = FakeStoriesGateway()
        let gate = StoryNoteSaveGate()
        await gateway.runBeforeAnswer { await gate.hold() }
        let model = StoriesViewModel(cache: InMemoryStoriesCache(), gateway: gateway)
        await model.configure(ownerUserID: UUID(), coupleID: UUID())
        let draft = StoryNoteDraft(text: "Earlier note")
        let saving = Task { await draft.save(using: model) }
        #expect(await waitUntil { await gate.isHeld })
        draft.text = "Earlier note with the new sentence"
        await gate.resume()
        #expect(await !saving.value)
        #expect(draft.text == "Earlier note with the new sentence")
        #expect(await gateway.noteTexts == ["Earlier note"])
        await gateway.runBeforeAnswer {}
        #expect(await draft.save(using: model))
        #expect(await gateway.noteTexts == ["Earlier note", "Earlier note with the new sentence"])
    }
    @Test(arguments: [false, true])
    func completedNoteSaveUpdatesTheBaselineWhileOriginalTextIsTypedAgain(removing: Bool) async {
        let gateway = FakeStoriesGateway()
        let gate = StoryNoteSaveGate()
        await gateway.runBeforeAnswer { await gate.hold() }
        let model = StoriesViewModel(cache: InMemoryStoriesCache(), gateway: gateway)
        await model.configure(ownerUserID: UUID(), coupleID: UUID())
        let draft = StoryNoteDraft(text: "Original note")
        draft.text = "Replacement note"
        let saving = Task { await draft.save(using: model, submitting: removing ? "" : draft.text) }
        #expect(await waitUntil { await gate.isHeld })
        draft.text = "Original note"
        await gate.resume()
        #expect(await !saving.value)
        #expect(draft.canShare)
        #expect(draft.savedText == (removing ? nil : "Replacement note"))
        await gateway.runBeforeAnswer {}
        #expect(await draft.save(using: model))
        #expect(draft.savedText == "Original note")
        #expect(!draft.canShare)
    }

    @Test func changingPrivacySessionReleasesSendStateAndProtectsTheNextDraft() async {
        let fixture = ChatTestFixture()
        let store = RetainedContentPendingStore()
        let replies = StoryReplies()
        let context = context(fixture: fixture, store: store)
        await replies.load(for: story(), header: header, context: context)
        replies.draft = "Previous session"
        await store.holdNext()
        let sending = Task { await replies.send() }
        #expect(await waitUntil { await store.isHeld })
        replies.clearForPrivacy()
        await replies.load(for: story(), header: header, context: context)
        replies.draft = "Current session"
        #expect(replies.canSend)
        await store.resume()
        #expect(await !sending.value)
        #expect(replies.draft == "Current session")
        #expect(replies.canSend)
    }
}

private actor StoryNoteSaveGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isHeld: Bool { continuation != nil }
    func hold() async { await withCheckedContinuation { continuation = $0 } }
    func resume() { continuation?.resume(); continuation = nil }
}
