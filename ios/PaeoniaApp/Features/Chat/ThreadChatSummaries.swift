import Foundation
import Observation

/// What the screens know about the couple's memory and story chats: whether a memory or
/// a story has a conversation yet, its last message, and whether the partner wrote
/// something the user has not read. The Questions tab lists the memory and story chats with
/// its question chats (`conversations(memories:stories:)`). It re-reads this phone's copy of
/// the chat summaries each time the chat cache changes. `ThreadChatLiveFeed` keeps that
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

    /// The memories and stories that someone has written about, each with its chat. A memory's
    /// notes are not messages, so a memory with notes and no messages has none.
    func conversations(memories: [MemoryRecord], stories: [Story]) -> [SubjectConversation] {
        memories.compactMap { conversation(about: .memory($0), chat: .memory($0.snapshot.memoryID)) }
            + stories.compactMap { conversation(about: .story($0), chat: .story($0.id)) }
            + summaries.values.compactMap { summary in
                guard case let .game(source) = summary.subject else { return nil }
                return SubjectConversation(
                    subject: .game(source), summary: summary, isUnread: isUnread(summary.subject))
            }
    }

    private func conversation(
        about subject: SubjectConversation.Subject,
        chat: ThreadChatSubject
    ) -> SubjectConversation? {
        summaries[chat].map { SubjectConversation(subject: subject, summary: $0, isUnread: isUnread(chat)) }
    }
}
