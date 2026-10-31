import Foundation

nonisolated enum StoryChainRoomMessage: GameLiveMessage {
    static let game = StoryChainLiveMessage.game

    case draft(StoryChainLiveMessage)
    case reaction(story: UUID, reaction: GameLiveReaction)
}
