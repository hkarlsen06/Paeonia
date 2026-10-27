import Foundation

/// One conversation per question, memory, story or finished game.
nonisolated enum ThreadChatSubject: Codable, Hashable, Sendable {
    case question(UUID)
    case memory(UUID)
    case story(UUID)
    case game(GameConversationSource)

    enum Kind: String, Codable, Sendable {
        case question = "daily_question"
        case memory, story, game
    }

    enum CodingKeys: String, CodingKey { case kind, id, gameSource }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .question: self = .question(try container.decode(UUID.self, forKey: .id))
        case .memory: self = .memory(try container.decode(UUID.self, forKey: .id))
        case .story: self = .story(try container.decode(UUID.self, forKey: .id))
        case .game: self = .game(try container.decode(GameConversationSource.self, forKey: .gameSource))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        if case let .game(source) = self { try container.encode(source, forKey: .gameSource) }
    }

    var kind: Kind {
        switch self {
        case .question: .question
        case .memory: .memory
        case .story: .story
        case .game: .game
        }
    }

    var id: UUID {
        switch self {
        case let .question(id), let .memory(id), let .story(id): id
        case let .game(source): source.id
        }
    }
}

extension ThreadChatSubject.Kind {
    nonisolated var createThreadFunction: String {
        switch self {
        case .question: "threads:create_daily_question_thread_with_message"
        case .memory: "threads:create_memory_thread_with_message"
        case .story: "threads:create_story_thread_with_message"
        case .game: "threads:create_game_thread_with_message"
        }
    }
}
