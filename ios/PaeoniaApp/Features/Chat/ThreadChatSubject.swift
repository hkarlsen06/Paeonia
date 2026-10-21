import Foundation

/// What a chat is about. A couple has one chat per question, one per memory (its comments)
/// and one per story (its replies). The chat code is the same for all three: the cache,
/// the send queue, the screen and the typing dots all work on a subject.
///
/// `id` is the question's, memory's or story's own id. No two subjects share one, so it
/// keys the chat's cache file and its queued messages (`subjectID` in the chat's data
/// layer). The kind decides which server function starts the
/// chat's thread. The raw values are the server's thread kinds
/// (`backend/convex/lib/threadSubjects.ts`).
nonisolated struct ThreadChatSubject: Codable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case question = "daily_question"
        case memory
        case story
    }

    let kind: Kind
    let id: UUID

    static func question(_ id: UUID) -> Self { Self(kind: .question, id: id) }
    static func memory(_ id: UUID) -> Self { Self(kind: .memory, id: id) }
    static func story(_ id: UUID) -> Self { Self(kind: .story, id: id) }
}

extension ThreadChatSubject.Kind {
    /// The server function that starts a chat of this kind with its first message.
    nonisolated var createThreadFunction: String {
        switch self {
        case .question: "threads:create_daily_question_thread_with_message"
        case .memory: "threads:create_memory_thread_with_message"
        case .story: "threads:create_story_thread_with_message"
        }
    }
}
