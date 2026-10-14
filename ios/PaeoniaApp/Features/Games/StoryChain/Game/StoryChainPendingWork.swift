import Foundation

// What this phone has queued for Story Chain and the server has not confirmed.
// The ids are chosen on this phone, so a line can name its story and a retry
// after a lost response sends the same ids again.

/// A story this person started. The story id is chosen on this phone.
nonisolated struct StoryChainQueuedStart: Codable, Equatable, Sendable {
    let storyID: UUID
    let gameID: UUID
    /// Nil when the starter writes their own first line.
    var openingID: String?
    var openingText: String?
    let createdAt: Date
}

/// A line this person wrote. The line id is chosen on this phone.
nonisolated struct StoryChainQueuedLine: Codable, Equatable, Sendable {
    let storyID: UUID
    let lineID: UUID
    /// The normalized text, as it goes to the server.
    let text: String
    let isLast: Bool
    /// The word this line gives to the next line.
    var dareWord: String?
    /// The suggested word's id. Nil for a word the person typed.
    var dareWordID: String?
    let createdAt: Date
}

/// A title this person gave to a story.
nonisolated struct StoryChainQueuedName: Codable, Equatable, Sendable {
    let storyID: UUID
    let title: String
}

/// The queued Story Chain writes of one person, as the screens need them. A
/// write the server refused for good is no longer in flight, so it drops out of
/// this value and the screen falls back to the server's state.
nonisolated struct StoryChainPendingWork: Equatable, Sendable {
    /// Oldest first.
    var starts: [StoryChainQueuedStart] = []
    /// Oldest first.
    var lines: [StoryChainQueuedLine] = []
    var names: [StoryChainQueuedName] = []
    /// Finished stories this person moved past, with the mark still on this phone.
    var seenStoryIDs: Set<UUID> = []
    /// A waiting move has had a try that did not get through, for any reason.
    /// Until then the move is on its first send, and the screen says nothing
    /// about it being on this phone, so a normal send never flashes that line.
    var isHeldOnPhone = false
    /// A waiting move was tried again and the attempt failed for a reason other
    /// than having no connection, such as the server refusing it. The waiting
    /// screen then says so instead of "saved on this phone".
    var lastSendFailedWhileOnline = false

    static let none = StoryChainPendingWork()

    var isEmpty: Bool {
        !hasMoveWaiting && seenStoryIDs.isEmpty
    }

    /// A move of the story (not a seen mark) waits to be sent.
    var hasMoveWaiting: Bool {
        !starts.isEmpty || !lines.isEmpty || !names.isEmpty
    }
}
