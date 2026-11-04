import Foundation

/// One conversation per question, memory, story or game kind, and the couple chat ("Just us"),
/// which is about nothing in particular. A couple has one couple chat, so it carries no id.
nonisolated enum ThreadChatSubject: Codable, Hashable, Sendable {
    case question(UUID)
    case memory(UUID)
    case story(UUID)
    case game(GameChatSubject)
    case couple

    enum Kind: String, Codable, Sendable {
        case question = "daily_question"
        case memory, story, game, couple
    }

    /// The key this phone stores the couple chat under. The chat cache, drafts and send queue
    /// belong to one signed-in person, and leaving the relationship clears them, so one fixed key
    /// is enough. It never goes to the server.
    static let coupleChatID = UUID(uuid: (0xC0, 0x09, 0x1E, 0x00, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x01))

    enum CodingKeys: String, CodingKey { case kind, id, gameSubject }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .question: self = .question(try container.decode(UUID.self, forKey: .id))
        case .memory: self = .memory(try container.decode(UUID.self, forKey: .id))
        case .story: self = .story(try container.decode(UUID.self, forKey: .id))
        case .game: self = .game(try container.decode(GameChatSubject.self, forKey: .gameSubject))
        case .couple: self = .couple
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        if case let .game(source) = self { try container.encode(source, forKey: .gameSubject) }
    }

    var kind: Kind {
        switch self {
        case .question: .question
        case .memory: .memory
        case .story: .story
        case .game: .game
        case .couple: .couple
        }
    }

    var id: UUID {
        switch self {
        case let .question(id), let .memory(id), let .story(id): id
        case let .game(source): source.id
        case .couple: Self.coupleChatID
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
        case .couple: "threads:create_couple_thread_with_message"
        }
    }
}

extension ThreadChatSubject {
    /// The `p_subject_id` the server knows this chat by. Nil for the couple chat, which the
    /// server finds by its couple.
    nonisolated var serverID: UUID? {
        self == .couple ? nil : id
    }
}
