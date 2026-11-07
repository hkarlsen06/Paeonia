import Foundation
import Observation

/// The replies to the story on screen. It holds the story's chat, the shared chat that
/// memory comments and question chats also use, so a reply written under the story goes
/// through the same send queue, works offline, and shows up in the chat sheet.
@Observable
final class StoryReplies {
    private(set) var chat: ThreadChatViewModel?
    var draft = "" {
        didSet {
            if let storyID { drafts[storyID] = draft }
        }
    }
    private var drafts: [UUID: String] = [:]
    private var privacySession = UUID()

    var hasUnsentReply: Bool { !draft.isEmpty || isSending }

    func clearForPrivacy() {
        privacySession = UUID()
        drafts = [:]
        storyID = nil
        draft = ""
        chat = nil
        justSent = false
        isSending = false
    }
    private(set) var isSending = false
    /// Briefly true after a reply went out, so the field can say so.
    private(set) var justSent = false
    private var storyID: UUID?

    /// Opens the chat of `story` from this phone's copy. Does nothing for the story already open.
    func load(for story: Story, header: ThreadChatHeader, context: ThreadChatContext) async {
        guard story.id != storyID else { return }
        storyID = story.id
        chat = nil
        draft = drafts[story.id] ?? ""
        justSent = false
        guard context.isAvailable else { return }
        let session = privacySession
        let loaded = await context.makeViewModel(subject: .story(story.id), header: header)
        guard storyID == story.id, privacySession == session else { return }
        chat = loaded
    }

    var canSend: Bool {
        chat != nil && !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Queues the draft as a reply. Returns false when it could not be saved on this phone,
    /// and the draft stays in the field.
    func send() async -> Bool {
        guard let chat, canSend else { return false }
        isSending = true
        let session = privacySession
        defer { if privacySession == session { isSending = false } }
        let submitted = draft
        let submittedStoryID = storyID
        guard await chat.send(submitted), privacySession == session else { return false }
        if let submittedStoryID, drafts[submittedStoryID] == submitted {
            drafts[submittedStoryID] = nil
        }
        guard storyID == submittedStoryID, draft == submitted else { return true }
        draft = ""
        justSent = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.justSent = false
        }
        return true
    }
}

extension ThreadChatHeader {
    /// The card at the top of a story's replies, so the conversation shows which story it is about.
    static func story(_ story: Story, people: StoryPeople) -> ThreadChatHeader {
        ThreadChatHeader(
            eyebrow: people.isOwn(story)
                ? String(localized: .chatHeaderYourStory)
                : String(localized: .chatHeaderStory(people.partnerName)),
            title: story.caption ?? "",
            detail: story.createdAt.formatted(date: .abbreviated, time: .shortened),
            photoAssetID: story.mediaAssetID
        )
    }
}
