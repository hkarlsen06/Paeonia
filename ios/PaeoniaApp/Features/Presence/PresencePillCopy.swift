import SwiftUI

extension PresenceCallout {
    /// A message says where it was written, above the message itself.
    var title: LocalizedStringResource {
        switch self {
        case let .message(message): PresencePlace.chatting(in: message.chat)
        case let .openedGame(kind): .presenceStatusOpenedGame(String(localized: kind.name))
        case let .typing(chat): Self.typing(in: chat)
        }
    }

    private static func typing(in chat: ThreadChatSubject) -> LocalizedStringResource {
        switch chat {
        case .couple: .presenceStatusTypingCouple
        case let .game(game): .presenceStatusTypingGame(String(localized: game.kind.name))
        case .question: .presenceStatusTypingQuestion
        case .memory: .presenceStatusTypingMemory
        case .story: .presenceStatusTypingStory
        }
    }
}

extension PresencePlace {
    /// "Here now", "Playing Mind Meld" or "In Just us".
    var title: LocalizedStringResource {
        switch self {
        case let .playing(kind): .presenceStatusPlaying(String(localized: kind.name))
        case let .chatting(chat): Self.chatting(in: chat)
        case .here: .presenceStatusHere
        }
    }

    static func chatting(in chat: ThreadChatSubject) -> LocalizedStringResource {
        switch chat {
        case .couple: .presenceStatusChattingCouple
        case let .game(game): .presenceStatusChattingGame(String(localized: game.kind.name))
        case .question: .presenceStatusChattingQuestion
        case .memory: .presenceStatusChattingMemory
        case .story: .presenceStatusChattingStory
        }
    }
}

extension PresencePillStatus {
    /// The callout while there is one, otherwise where the partner is.
    var headline: LocalizedStringResource {
        callout?.title ?? place.title
    }

    /// "Robin is here. Playing Mind Meld", for VoiceOver on the avatar.
    func accessibilityLabel(partnerName: String) -> LocalizedStringResource {
        if callout == nil, place == .here { return .presenceAvatarAccessibilityLabelHere(partnerName) }
        return .presenceAvatarAccessibilityLabel(partnerName, String(localized: headline))
    }
}
