import Foundation
import SwiftUI

extension StoryChainViewModel {
    var canSendLiveReaction: Bool {
        guard isRunning, isActive, story != nil, let live, live.partnerActivity != .away else { return false }
        switch phase {
        case .writing, .waitingForLine, .naming, .waitingForName: return true
        default: return false
        }
    }

    func sendLiveReaction(_ reaction: GameLiveReaction) {
        guard canSendLiveReaction, let story, let liveChannel else { return }
        liveChannel.send(.reaction(story: story.id, reaction: reaction))
        liveReactions.show(reaction)
        PaeoniaHaptics.selection()
    }

    func receiveLiveReaction(_ reaction: GameLiveReaction, storyID: UUID) {
        guard canSendLiveReaction, story?.id == storyID else { return }
        liveReactions.show(reaction)
        PaeoniaHaptics.partnerDrawingReceived()
        var announcement = AttributedString(String(localized: .gamesLiveReactionReceived(partnerName, reaction.glyph)))
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
    }
}
