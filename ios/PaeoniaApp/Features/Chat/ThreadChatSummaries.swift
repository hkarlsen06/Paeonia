import Foundation
import Observation

/// What the screens know about the couple's memory and story chats: whether a memory or
/// a story has a conversation yet, its last message, and whether the partner wrote
/// something the user has not read. The Questions tab lists the story chats with its
/// question chats (`storyConversations(for:)`). It re-reads this phone's copy of the chat
/// summaries each time the chat cache changes. `ThreadChatLiveFeed` keeps that
/// copy current.
@MainActor
@Observable
final class ThreadChatSummaries {
    private(set) var summaries: [ThreadChatSubject: ThreadChatSummary] = [:]
    private var readMarks: [UUID: Date] = [:]
    private var currentUserID: UUID?
    @ObservationIgnored private let service: any ThreadChatServicing

    init(service: any ThreadChatServicing) {
        self.service = service
    }

    /// Follows the chat cache for `ownerUserID` until the calling task is cancelled.
    func observe(ownerUserID: UUID?) async {
        guard let ownerUserID else {
            summaries = [:]
            readMarks = [:]
            currentUserID = nil
            return
        }
        currentUserID = ownerUserID
        await reload(ownerUserID: ownerUserID)
        for await change in LocalStoreChanges.changes(in: .threadChat) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == ownerUserID else { continue }
            await reload(ownerUserID: ownerUserID)
        }
    }

    private func reload(ownerUserID: UUID) async {
        let cached = await service.cachedThreadSummaries(ownerUserID: ownerUserID)
        let marks = await service.chatReadMarks(ownerUserID: ownerUserID)
        guard currentUserID == ownerUserID else { return }
        summaries = Dictionary(cached.map { ($0.subject, $0) }, uniquingKeysWith: { _, latest in latest })
        readMarks = marks
    }

    /// The chat about `subject` once someone has written in it.
    func summary(for subject: ThreadChatSubject) -> ThreadChatSummary? {
        summaries[subject]
    }

    /// The newest message of the chat, as the preview line shows it.
    func preview(for subject: ThreadChatSubject) -> String? {
        summaries[subject]?.lastMessagePreview
    }

    /// The partner wrote in this chat after the user last read it.
    func isUnread(_ subject: ThreadChatSubject) -> Bool {
        guard let summary = summaries[subject], let currentUserID else { return false }
        return summary.isUnread(by: currentUserID, readThrough: readMarks[summary.threadID])
    }

    /// The stories in `stories` that someone has written about, each with its chat.
    func storyConversations(for stories: [Story]) -> [StoryConversation] {
        stories.compactMap { story in
            summaries[.story(story.id)].map { summary in
                StoryConversation(story: story, summary: summary, isUnread: isUnread(summary.subject))
            }
        }
    }
}
