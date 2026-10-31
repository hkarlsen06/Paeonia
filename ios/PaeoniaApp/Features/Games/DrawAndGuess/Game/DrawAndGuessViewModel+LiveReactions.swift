import Foundation
import SwiftUI

extension DrawAndGuessViewModel {
    var canSendLiveReaction: Bool {
        guard isActive, !isStopped, let round, !round.isFinished,
              let live else { return false }
        guard live.partnerActivity == .drawing || live.partnerActivity == .watching else { return false }
        switch phase {
        case .drawing, .watchingLive, .guessing, .waitingForGuess: return true
        default: return false
        }
    }

    func sendLiveReaction(_ reaction: GameLiveReaction) {
        guard canSendLiveReaction, let round, let liveGuessChannel else { return }
        liveGuessChannel.send(.reaction(round: round.id, reaction: reaction))
        liveReactions.show(reaction)
        PaeoniaHaptics.selection()
    }

    func receiveLiveReaction(_ reaction: GameLiveReaction, roundID: UUID) {
        guard canSendLiveReaction, round?.id == roundID else { return }
        liveReactions.show(reaction)
        if !board.isStrokeInProgress { PaeoniaHaptics.partnerDrawingReceived() }
        var announcement = AttributedString(
            String(localized: .gamesLiveReactionReceived(partnerName, reaction.glyph))
        )
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
    }

    func clearLiveReactions() {
        liveReactions.clear()
    }
}
