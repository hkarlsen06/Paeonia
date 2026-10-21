import Foundation

/// What `search:search_couple_content` returns: the matches in the couple's questions, answers,
/// chats and Story Chain stories. The phone searches memories and stories itself.
nonisolated struct RemoteSearchResponse: Decodable, Equatable, Sendable {
    struct Question: Decodable, Equatable, Sendable {
        let questionID: UUID
        let prompt: String
        let topicTitle: String?
        /// The latest day the question came back on (`yyyy-MM-dd`).
        let localDate: String

        enum CodingKeys: String, CodingKey {
            case questionID = "question_id"
            case prompt
            case topicTitle = "topic_title"
            case localDate = "local_date"
        }
    }

    struct Answer: Decodable, Equatable, Sendable {
        let answerID: UUID
        let questionID: UUID
        let authorUserID: UUID
        let snippet: String
        let prompt: String
        let topicTitle: String?
        let answeredAt: Date

        enum CodingKeys: String, CodingKey {
            case answerID = "answer_id"
            case questionID = "question_id"
            case authorUserID = "author_user_id"
            case snippet
            case prompt
            case topicTitle = "topic_title"
            case answeredAt = "answered_at"
        }
    }

    struct Message: Decodable, Equatable, Sendable {
        let messageID: UUID
        /// The thread's kind. The app opens `daily_question`, `memory` and `story` chats and skips others.
        let threadKind: String
        let senderUserID: UUID
        let snippet: String
        let createdAt: Date
        let questionID: UUID?
        let memoryID: UUID?
        let storyID: UUID?
        /// The question's wording, the memory's title or the story's caption.
        let contextTitle: String?
        let topicTitle: String?

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
            case threadKind = "thread_kind"
            case senderUserID = "sender_user_id"
            case snippet
            case createdAt = "created_at"
            case questionID = "question_id"
            case memoryID = "memory_id"
            case storyID = "story_id"
            case contextTitle = "context_title"
            case topicTitle = "topic_title"
        }
    }

    struct StoryChainStory: Decodable, Equatable, Sendable {
        let storyID: UUID
        let title: String?
        let snippet: String
        let finishedAt: Date

        enum CodingKeys: String, CodingKey {
            case storyID = "story_id"
            case title
            case snippet
            case finishedAt = "finished_at"
        }
    }

    let questions: [Question]
    let answers: [Answer]
    let messages: [Message]
    let storyChain: [StoryChainStory]

    enum CodingKeys: String, CodingKey {
        case questions
        case answers
        case messages
        case storyChain = "story_chain"
    }
}

/// Searches the couple's questions, answers, chats and Story Chain stories on the server.
nonisolated protocol SearchServing: Sendable {
    func search(_ query: SearchQuery, locale: Locale) async throws -> RemoteSearchResponse
}

nonisolated struct LiveSearchService: SearchServing {
    private struct Request: Encodable {
        let query: String
        let locale: String

        enum CodingKeys: String, CodingKey {
            case query = "p_query"
            case locale = "p_locale"
        }
    }

    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func search(_ query: SearchQuery, locale: Locale) async throws -> RemoteSearchResponse {
        // The server rebuilds the words from the text, so it gets the same words the phone marks.
        let request = Request(query: query.words.joined(separator: " "), locale: Self.languageCode(of: locale))
        return try await client.query("search:search_couple_content", args: request)
    }

    /// The two languages the app has. Questions come back in the one that matches.
    static func languageCode(of locale: Locale) -> String {
        switch locale.language.languageCode?.identifier {
        case "nb", "no", "nn": "nb"
        default: "en"
        }
    }
}

/// Used in previews and when no backend client is configured.
nonisolated struct NoOpSearchService: SearchServing {
    // swiftlint:disable:next async_without_await
    func search(_ query: SearchQuery, locale: Locale) async throws -> RemoteSearchResponse {
        RemoteSearchResponse(questions: [], answers: [], messages: [], storyChain: [])
    }
}
