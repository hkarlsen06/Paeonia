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

    func sendLiveReaction(_ reaction: DrawAndGuessLiveReaction) {
        guard canSendLiveReaction, let round, let liveGuessChannel else { return }
        liveGuessChannel.send(.reaction(round: round.id, reaction: reaction))
        showLiveReaction(reaction)
        PaeoniaHaptics.selection()
    }

    func receiveLiveReaction(_ reaction: DrawAndGuessLiveReaction, roundID: UUID) {
        guard canSendLiveReaction, round?.id == roundID else { return }
        showLiveReaction(reaction)
        if !board.isStrokeInProgress { PaeoniaHaptics.partnerDrawingReceived() }
        var announcement = AttributedString(
            String(localized: .gamesDrawAndGuessLiveReactionReceived(partnerName, reaction.glyph))
        )
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func showLiveReaction(_ reaction: DrawAndGuessLiveReaction) {
        liveReactions.removeAll { Date().timeIntervalSince($0.start) >= DrawAndGuessReactionFlight.duration }
        liveReactions.append(DrawAndGuessReactionFlight(reaction: reaction))
        liveReactions = Array(liveReactions.suffix(20))
        liveReactionTask?.cancel()
        liveReactionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DrawAndGuessReactionFlight.duration))
            guard !Task.isCancelled else { return }
            self?.liveReactions.removeAll()
        }
    }

    func clearLiveReactions() {
        liveReactionTask?.cancel()
        liveReactionTask = nil
        liveReactions.removeAll()
    }
}
