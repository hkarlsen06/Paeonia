import SwiftUI

extension PresenceCallout {
    /// A message says where it was written, above the message itself, and a notification its title.
    /// The partner's notification arrives in words already, so every case is a plain string.
    var title: String {
        switch self {
        case let .message(message): String(localized: PresencePlace.chatting(in: message.chat))
        case let .openedGame(kind): String(localized: .presenceStatusOpenedGame(String(localized: kind.name)))
        case .openedDrawing: String(localized: .presenceStatusOpenedDrawing)
        case let .typing(chat): String(localized: Self.typing(in: chat))
        case let .update(update): update.title ?? update.message
        }
    }

    /// The message, or a notification's text under its title.
    var detail: String? {
        switch self {
        case let .message(message): message.preview
        case .openedGame, .openedDrawing, .typing: nil
        case let .update(update): update.title == nil ? nil : update.message
        }
    }

    func accessibilityLabel(partnerName: String) -> String {
        switch self {
        case let .message(message):
            String(localized: .presenceNoticeMessageAccessibilityLabel(partnerName, message.preview))
        case let .update(update):
            [update.title, update.message].compactMap(\.self).joined(separator: ". ")
        case .openedGame, .openedDrawing, .typing:
            title
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
        case .drawing: .presenceStatusDrawing
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
    var headline: String {
        callout?.title ?? String(localized: place.title)
    }

    /// "Robin is here. Playing Mind Meld", for VoiceOver on the avatar.
    func accessibilityLabel(partnerName: String) -> LocalizedStringResource {
        if callout == nil, place == .here { return .presenceAvatarAccessibilityLabelHere(partnerName) }
        return .presenceAvatarAccessibilityLabel(partnerName, headline)
    }
}
