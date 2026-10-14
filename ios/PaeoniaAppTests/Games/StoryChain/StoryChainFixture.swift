import Foundation
@testable import PaeoniaApp

/// Deterministic Story Chain states. The signed-in person is `me`, and the
/// partner is `partner`. Every date counts from `now`.
enum StoryChainFixture {
    static let me = UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID()
    static let partner = UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID()
    static let couple = UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID()
    static let gameID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001") ?? UUID()
    static let storyID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000001") ?? UUID()
    static let nextStoryID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002") ?? UUID()
    static let now = Date(timeIntervalSince1970: 1_784_203_200)

    static func settings() -> RemoteGameSettings {
        RemoteGameSettings(
            coupleID: couple,
            playStyle: .together,
            language: .en,
            updatedByUserID: me,
            createdAt: now,
            updatedAt: now
        )
    }

    static func game(
        _ state: StoryChainGameState,
        turn: UUID,
        current: UUID? = storyID,
        stories: Int = 1,
        version: Int = 1,
        id: UUID = gameID
    ) -> RemoteStoryChainGame {
        RemoteStoryChainGame(
            id: id,
            state: state,
            turnUserID: turn,
            turnNumber: 3,
            currentStoryID: current,
            storyCount: stories,
            finishedCount: 0,
            turnStartedAt: now,
            version: version
        )
    }

    /// A line's id follows its number, so two states built the same way are equal.
    static func line(_ number: Int, by author: UUID, id: UUID? = nil) -> RemoteStoryLine {
        RemoteStoryLine(
            id: id ?? UUID(uuidString: String(format: "cccccccc-0000-4000-8000-%012d", number)) ?? UUID(),
            number: number,
            authorUserID: author,
            text: "Line \(number).",
            dareWord: nil,
            createdAt: now.addingTimeInterval(Double(number) * 60)
        )
    }

    /// Lines that alternate between the two people, `starter` first.
    static func lines(_ count: Int, starter: UUID) -> [RemoteStoryLine] {
        (0..<count).map { index in
            line(index + 1, by: index.isMultiple(of: 2) ? starter : (starter == me ? partner : me))
        }
    }

    static func story(
        _ state: StoryChainStoryState,
        id: UUID = storyID,
        number: Int = 1,
        starter: UUID = partner,
        lines: [RemoteStoryLine] = [],
        titledBy: UUID = partner,
        seenByMe: Bool = false,
        opening: String? = nil
    ) -> RemoteStoryChainStory {
        RemoteStoryChainStory(
            id: id,
            storyNumber: number,
            starterUserID: starter,
            openingID: opening.map { _ in "en-opening" },
            openingText: opening,
            state: state,
            lines: lines,
            lastLineUserID: state == .writing ? nil : lines.last?.authorUserID,
            title: state == .finished ? "The night bus" : nil,
            titledByUserID: state == .finished ? titledBy : nil,
            finishedAt: state == .finished ? now : nil,
            seenByMe: seenByMe,
            starredByMe: false,
            createdAt: now,
            updatedAt: now
        )
    }

    static func state(
        _ game: RemoteStoryChainGame?,
        current: RemoteStoryChainStory? = nil,
        previous: RemoteStoryChainStory? = nil,
        userID: UUID = me
    ) -> RemoteStoryChainState {
        RemoteStoryChainState(
            userID: userID,
            partnerUserID: partner,
            coupleID: couple,
            dataEpoch: "",
            game: game,
            currentStory: current,
            previousStory: previous,
            openingChoices: nil,
            wordChoices: nil
        )
    }

    static func queuedLine(
        story: UUID = storyID,
        id: UUID = UUID(),
        isLast: Bool = false
    ) -> StoryChainQueuedLine {
        StoryChainQueuedLine(storyID: story, lineID: id, text: "A queued line.", isLast: isLast, createdAt: now)
    }

    static func queuedStart(story: UUID = nextStoryID, game: UUID = gameID) -> StoryChainQueuedStart {
        StoryChainQueuedStart(
            storyID: story,
            gameID: game,
            openingID: "en-opening",
            openingText: "A key opened nothing in town.",
            createdAt: now
        )
    }
}
