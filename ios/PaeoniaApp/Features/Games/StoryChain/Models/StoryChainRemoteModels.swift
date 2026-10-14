import Foundation

/// Where the couple's Story Chain game is. `choosing_opening` is the time
/// between two stories, and also before the first one.
nonisolated enum StoryChainGameState: String, Codable, Sendable {
    case choosingOpening = "choosing_opening"
    case writing
    case titling
}

nonisolated enum StoryChainStoryState: String, Codable, Sendable {
    /// Lines are being added.
    case writing
    /// The last line is written and the partner is choosing a title.
    case titling
    case finished
}

/// One of the three opening lines Paeonia offers. Only the partner whose turn it
/// is to start a story receives these.
nonisolated struct RemoteStoryOpening: Codable, Equatable, Identifiable, Sendable {
    let openingID: String
    let text: String

    var id: String { openingID }

    enum CodingKeys: String, CodingKey {
        case openingID = "opening_id"
        case text
    }
}

/// One of the three dare words Paeonia suggests. Only the partner whose turn it
/// is to write receives these.
nonisolated struct RemoteStoryDareWord: Codable, Equatable, Identifiable, Sendable {
    let wordID: String
    let word: String

    var id: String { wordID }

    enum CodingKeys: String, CodingKey {
        case wordID = "word_id"
        case word
    }
}

nonisolated struct RemoteStoryChainGame: Codable, Equatable, Sendable {
    let id: UUID
    let state: StoryChainGameState
    /// The partner who acts next.
    let turnUserID: UUID
    /// Seeds the suggested openings and words, so they stay the same for the turn.
    let turnNumber: Int
    let currentStoryID: UUID?
    let storyCount: Int
    let finishedCount: Int
    let turnStartedAt: Date
    /// Goes up with every change to the game.
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case turnUserID = "turn_user_id"
        case turnNumber = "turn_number"
        case currentStoryID = "current_story_id"
        case storyCount = "story_count"
        case finishedCount = "finished_count"
        case turnStartedAt = "turn_started_at"
        case version
    }
}

nonisolated struct RemoteStoryLine: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// 1 for the first line. The opening is not a line.
    let number: Int
    let authorUserID: UUID
    let text: String
    /// The word this line gave to the next line. Nil when the line gave none.
    let dareWord: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case authorUserID = "author_user_id"
        case text
        case dareWord = "dare_word"
        case createdAt = "created_at"
    }
}

nonisolated struct RemoteStoryChainStory: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let storyNumber: Int
    let starterUserID: UUID
    /// Nil when the starter began with their own line.
    let openingID: String?
    let openingText: String?
    var state: StoryChainStoryState
    /// Oldest first.
    var lines: [RemoteStoryLine]
    var lastLineUserID: UUID?
    var title: String?
    var titledByUserID: UUID?
    var finishedAt: Date?
    /// This person has moved past the finished story. Meaningless before it finishes.
    var seenByMe: Bool
    /// This person's own private star. The partner's is never sent.
    var starredByMe: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storyNumber = "story_number"
        case starterUserID = "starter_user_id"
        case openingID = "opening_id"
        case openingText = "opening_text"
        case state
        case lines
        case lastLineUserID = "last_line_user_id"
        case title
        case titledByUserID = "titled_by_user_id"
        case finishedAt = "finished_at"
        case seenByMe = "seen_by_me"
        case starredByMe = "starred_by_me"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `storyChain:get_story_chain`: everything the Story Chain screens show.
/// `settings` come from `games:get_game_settings`, not from this query.
nonisolated struct RemoteStoryChainState: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// The server's data epoch (`PAEONIA_DATA_EPOCH`). It changes only after a backup
    /// restore or a hand edit of the games, and then the server's copy wins.
    let dataEpoch: String
    let game: RemoteStoryChainGame?
    /// The story with the highest number.
    var currentStory: RemoteStoryChainStory?
    /// The story before the current one, so a partner who missed a finished
    /// story still sees it after the next one started.
    var previousStory: RemoteStoryChainStory?
    /// Only the partner who starts the next story, while the game is choosing one.
    let openingChoices: [RemoteStoryOpening]?
    /// Only the partner whose turn it is to write.
    let wordChoices: [RemoteStoryDareWord]?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case dataEpoch = "data_epoch"
        case game
        case currentStory = "current_story"
        case previousStory = "previous_story"
        case openingChoices = "opening_choices"
        case wordChoices = "word_choices"
    }

    /// This state is behind `other`: the same person and game, and a lower game
    /// version. A state without a game is never older, so a new game replaces it.
    /// The cache keeps the newer state when a late read arrives.
    func isOlder(than other: RemoteStoryChainState) -> Bool {
        guard userID == other.userID,
              dataEpoch == other.dataEpoch,
              let game,
              let otherGame = other.game,
              game.id == otherGame.id
        else {
            return false
        }
        return game.version < otherGame.version
    }
}

// MARK: - History

/// One finished story in "Our stories".
nonisolated struct RemoteStoryChainHistoryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let storyNumber: Int
    let title: String
    let firstLine: String
    let lineCount: Int
    let finishedAt: Date
    var starredByMe: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case storyNumber = "story_number"
        case title
        case firstLine = "first_line"
        case lineCount = "line_count"
        case finishedAt = "finished_at"
        case starredByMe = "starred_by_me"
    }
}

/// `storyChain:get_story_chain_history`: finished stories, newest first.
nonisolated struct RemoteStoryChainHistoryPage: Codable, Equatable, Sendable {
    let stories: [RemoteStoryChainHistoryItem]
    /// Pass this as `p_before_story_number` for the next page. Nil on the last page.
    let nextBeforeStoryNumber: Int?

    enum CodingKeys: String, CodingKey {
        case stories
        case nextBeforeStoryNumber = "next_before_story_number"
    }
}

// MARK: - Mutation results

// `storyChain:ensure_story_chain_game` returns `RemoteEnsureGameResult`.

nonisolated struct RemoteStartStoryResult: Decodable, Equatable, Sendable {
    let storyID: UUID
    let storyNumber: Int

    enum CodingKeys: String, CodingKey {
        case storyID = "story_id"
        case storyNumber = "story_number"
    }
}

nonisolated struct RemoteAddStoryLineResult: Decodable, Equatable, Sendable {
    let lineID: UUID
    let number: Int
    /// `titling` after a last line.
    let storyState: StoryChainStoryState

    enum CodingKeys: String, CodingKey {
        case lineID = "line_id"
        case number
        case storyState = "story_state"
    }
}

nonisolated struct RemoteNameStoryResult: Decodable, Equatable, Sendable {
    let storyID: UUID
    /// The title as the server kept it, after trimming.
    let title: String

    enum CodingKeys: String, CodingKey {
        case storyID = "story_id"
        case title
    }
}

nonisolated struct RemoteStoryStarResult: Decodable, Equatable, Sendable {
    let storyID: UUID
    let starred: Bool

    enum CodingKeys: String, CodingKey {
        case storyID = "story_id"
        case starred
    }
}
