import Foundation

/// A photo, with an optional caption, that one partner shares as a small check-in
/// (`backend/convex/stories.ts`). It shows on Home for `lifetime` after it was posted,
/// then stays in the Stories section of Memories until its author deletes it.
nonisolated struct Story: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let authorUserID: UUID
    let mediaAssetID: UUID
    let caption: String?
    let createdAt: Date
    /// When the partner first opened it. Nil until then.
    var seenAt: Date?

    /// How long a story shows on Home.
    static let lifetime: TimeInterval = 24 * 60 * 60
    /// The composer caps captions at this many characters.
    static let maxCaptionLength = 100

    var expiresAt: Date {
        createdAt.addingTimeInterval(Self.lifetime)
    }

    func isOnHome(at now: Date) -> Bool {
        now < expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorUserID = "author_user_id"
        case mediaAssetID = "media_asset_id"
        case caption
        case createdAt = "created_at"
        case seenAt = "seen_at"
    }
}

/// A partner's short note, shown in a bubble over their avatar on Home for a day after
/// it was set. Each partner has at most one, and a new note replaces it.
nonisolated struct StoryNote: Codable, Equatable, Sendable {
    let userID: UUID
    let text: String
    let createdAt: Date

    /// The note editor caps notes at this many characters.
    static let maxLength = 60

    func isOnHome(at now: Date) -> Bool {
        now < createdAt.addingTimeInterval(Story.lifetime)
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case text
        case createdAt = "created_at"
    }
}

/// The couple's stories, newest first, and both partners' notes, as this phone knows them.
nonisolated struct StoriesSnapshot: Codable, Equatable, Sendable {
    var stories: [Story] = []
    var notes: [StoryNote] = []

    /// `userID`'s note while it is still on Home.
    func note(of userID: UUID?, at now: Date) -> StoryNote? {
        notes.first { $0.userID == userID && $0.isOnHome(at: now) }
    }
}

/// The result of `stories:get_stories`.
nonisolated struct RemoteStories: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let stories: [Story]
    let notes: [StoryNote]

    var snapshot: StoriesSnapshot {
        StoriesSnapshot(stories: stories, notes: notes)
    }

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case stories
        case notes
    }
}

/// One person's stories as Home shows them.
nonisolated enum StoryRingState: Equatable, Sendable {
    /// Nothing posted in the last day.
    case noStory
    /// Stories the viewer has not opened yet.
    case unseen
    /// Every story was opened already.
    case seen
}

/// Pure rules for which stories show where, so the views and tests share them.
nonisolated enum StoryTimeline {
    /// `author`'s stories still on Home, oldest first, which is the order they play in.
    static func onHome(_ stories: [Story], author: UUID?, at now: Date) -> [Story] {
        stories
            .filter { $0.authorUserID == author && $0.isOnHome(at: now) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The partner's ring. A story counts as seen once `seenAt` is set, by the server
    /// or by this phone right after it opened it.
    static func partnerRing(_ stories: [Story], partner: UUID?, at now: Date) -> StoryRingState {
        let shown = onHome(stories, author: partner, at: now)
        if shown.isEmpty { return .noStory }
        return shown.contains { $0.seenAt == nil } ? .unseen : .seen
    }

    /// Where the partner's stories start playing: the oldest one not opened yet,
    /// or the first one when all were opened.
    static func startIndex(in stories: [Story]) -> Int {
        stories.firstIndex { $0.seenAt == nil } ?? 0
    }
}
