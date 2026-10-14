import Foundation

/// `storyChain:ensure_story_chain_game`.
nonisolated struct RemoteEnsureStoryChainResult: Decodable, Equatable, Sendable {
    let gameID: UUID
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case created
    }
}

/// The Story Chain backend functions (`backend/convex/storyChain.ts`) on top of
/// the shared ones. Writes that take a client operation are safe to retry: the
/// server runs each operation id once.
nonisolated protocol StoryChainGateway: GamesGateway {
    func ensureStoryChainGame() async throws -> RemoteEnsureStoryChainResult
    /// One-shot read of what the live feed follows.
    func loadStoryChain() async throws -> RemoteStoryChainState
    /// One story by id, also one that is no longer among the current and previous
    /// stories. Nil when the couple has no such story.
    func loadStory(id: UUID) async throws -> RemoteStoryChainStory?

    func startStory(
        _ start: StoryChainQueuedStart,
        operation: SyncClientOperation
    ) async throws -> RemoteStartStoryResult
    func addStoryLine(
        _ line: StoryChainQueuedLine,
        operation: SyncClientOperation
    ) async throws -> RemoteAddStoryLineResult
    func nameStory(_ name: StoryChainQueuedName, operation: SyncClientOperation) async throws -> RemoteNameStoryResult
    /// This person moved past the finished story. The server keeps the first
    /// time, so a retry is safe.
    func markStorySeen(storyID: UUID) async throws
    /// Private and safe to retry. The partner is not told.
    func setStoryStar(storyID: UUID, starred: Bool) async throws -> RemoteStoryStarResult

    /// A page of the couple's finished stories, newest first, before
    /// `beforeStoryNumber`. With `starredOnly`, only the stories this person starred.
    func loadStoryChainHistory(
        starredOnly: Bool,
        beforeStoryNumber: Int?,
        limit: Int
    ) async throws -> RemoteStoryChainHistoryPage
}

nonisolated extension LiveGamesGateway: StoryChainGateway {
    func ensureStoryChainGame() async throws -> RemoteEnsureStoryChainResult {
        try await client.mutation("storyChain:ensure_story_chain_game")
    }

    func loadStoryChain() async throws -> RemoteStoryChainState {
        try await client.query("storyChain:get_story_chain")
    }

    func loadStory(id: UUID) async throws -> RemoteStoryChainStory? {
        try await client.query("storyChain:get_story_chain_story", args: StoryRequest(storyID: id))
    }

    func startStory(
        _ start: StoryChainQueuedStart,
        operation: SyncClientOperation
    ) async throws -> RemoteStartStoryResult {
        try await client.mutation(
            "storyChain:start_story",
            args: StartStoryRequest(start: start, operation: operation)
        )
    }

    func addStoryLine(
        _ line: StoryChainQueuedLine,
        operation: SyncClientOperation
    ) async throws -> RemoteAddStoryLineResult {
        try await client.mutation(
            "storyChain:add_story_line",
            args: AddStoryLineRequest(line: line, operation: operation)
        )
    }

    func nameStory(
        _ name: StoryChainQueuedName,
        operation: SyncClientOperation
    ) async throws -> RemoteNameStoryResult {
        try await client.mutation(
            "storyChain:name_story",
            args: NameStoryRequest(name: name, operation: operation)
        )
    }

    func markStorySeen(storyID: UUID) async throws {
        try await client.mutation("storyChain:mark_story_seen", args: StoryRequest(storyID: storyID))
    }

    func setStoryStar(storyID: UUID, starred: Bool) async throws -> RemoteStoryStarResult {
        try await client.mutation(
            "storyChain:set_story_star",
            args: StarRequest(storyID: storyID, starred: starred)
        )
    }

    func loadStoryChainHistory(
        starredOnly: Bool,
        beforeStoryNumber: Int?,
        limit: Int
    ) async throws -> RemoteStoryChainHistoryPage {
        try await client.query(
            "storyChain:get_story_chain_history",
            args: HistoryRequest(starredOnly: starredOnly, beforeStoryNumber: beforeStoryNumber, limit: limit)
        )
    }
}

// MARK: - Request bodies

nonisolated private struct StoryRequest: Encodable {
    let storyID: UUID

    enum CodingKeys: String, CodingKey {
        case storyID = "p_story_id"
    }
}

nonisolated private struct StarRequest: Encodable {
    let storyID: UUID
    let starred: Bool

    enum CodingKeys: String, CodingKey {
        case storyID = "p_story_id"
        case starred = "p_starred"
    }
}

nonisolated private struct HistoryRequest: Encodable {
    let starredOnly: Bool
    /// Nil for the first page, so the key is left out.
    let beforeStoryNumber: Int?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case starredOnly = "p_starred_only"
        case beforeStoryNumber = "p_before_story_number"
        case limit = "p_limit"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(starredOnly, forKey: .starredOnly)
        try container.encodeIfPresent(beforeStoryNumber.map(Double.init), forKey: .beforeStoryNumber)
        // `v.number()` in the backend, so a Double.
        try container.encode(Double(limit), forKey: .limit)
    }
}

nonisolated private struct StartStoryRequest: Encodable {
    let gameID: UUID
    let storyID: UUID
    let openingID: String?
    let operation: GameClientOperationFields

    init(start: StoryChainQueuedStart, operation: SyncClientOperation) {
        gameID = start.gameID
        storyID = start.storyID
        openingID = start.openingID
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case storyID = "p_story_id"
        case openingID = "p_opening_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gameID, forKey: .gameID)
        try container.encode(storyID, forKey: .storyID)
        // No opening means the starter writes their own first line: the key is left out.
        try container.encodeIfPresent(openingID, forKey: .openingID)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct AddStoryLineRequest: Encodable {
    let storyID: UUID
    let lineID: UUID
    let text: String
    let isLast: Bool
    let dareWord: String?
    let dareWordID: String?
    let operation: GameClientOperationFields

    init(line: StoryChainQueuedLine, operation: SyncClientOperation) {
        storyID = line.storyID
        lineID = line.lineID
        text = line.text
        isLast = line.isLast
        // A suggested word goes by its id and the server takes its text from the
        // list. Only a typed word sends its text.
        dareWord = line.dareWordID == nil ? line.dareWord : nil
        dareWordID = line.dareWordID
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case storyID = "p_story_id"
        case lineID = "p_line_id"
        case text = "p_text"
        case isLast = "p_is_last"
        case dareWord = "p_dare_word"
        case dareWordID = "p_dare_word_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storyID, forKey: .storyID)
        try container.encode(lineID, forKey: .lineID)
        try container.encode(text, forKey: .text)
        try container.encode(isLast, forKey: .isLast)
        try container.encodeIfPresent(dareWord, forKey: .dareWord)
        try container.encodeIfPresent(dareWordID, forKey: .dareWordID)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct NameStoryRequest: Encodable {
    let storyID: UUID
    let title: String
    let operation: GameClientOperationFields

    init(name: StoryChainQueuedName, operation: SyncClientOperation) {
        storyID = name.storyID
        title = name.title
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case storyID = "p_story_id"
        case title = "p_title"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storyID, forKey: .storyID)
        try container.encode(title, forKey: .title)
        try operation.encode(to: encoder)
    }
}

// MARK: - No Convex URL

// The protocol is async, and these stand-ins fail at once.
// swiftlint:disable async_without_await
nonisolated extension UnavailableGamesGateway: StoryChainGateway {
    func ensureStoryChainGame() async throws -> RemoteEnsureStoryChainResult {
        throw Unavailable()
    }

    func loadStoryChain() async throws -> RemoteStoryChainState {
        throw Unavailable()
    }

    func loadStory(id _: UUID) async throws -> RemoteStoryChainStory? {
        throw Unavailable()
    }

    func startStory(
        _: StoryChainQueuedStart,
        operation _: SyncClientOperation
    ) async throws -> RemoteStartStoryResult {
        throw Unavailable()
    }

    func addStoryLine(
        _: StoryChainQueuedLine,
        operation _: SyncClientOperation
    ) async throws -> RemoteAddStoryLineResult {
        throw Unavailable()
    }

    func nameStory(
        _: StoryChainQueuedName,
        operation _: SyncClientOperation
    ) async throws -> RemoteNameStoryResult {
        throw Unavailable()
    }

    func markStorySeen(storyID _: UUID) async throws {
        throw Unavailable()
    }

    func setStoryStar(storyID _: UUID, starred _: Bool) async throws -> RemoteStoryStarResult {
        throw Unavailable()
    }

    func loadStoryChainHistory(
        starredOnly _: Bool,
        beforeStoryNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteStoryChainHistoryPage {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await
