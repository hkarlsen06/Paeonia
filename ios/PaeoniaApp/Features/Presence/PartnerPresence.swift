import SwiftUI

/// Where the partner is while they have Paeonia open, decoded from `appPresence:get_partner_presence`
/// at the boundary.
nonisolated struct PartnerPresence: Equatable, Sendable {
    /// The game screens the partner has open, the one they opened last at the end.
    var games: [GameKind] = []
    /// The chat screen the partner has open.
    var chat: ThreadChatSubject?
    /// The chat the partner types in.
    var typing: ThreadChatSubject?

    /// The game the partner opened last, which the avatar names and Join opens.
    var game: GameKind? { games.last }

    /// This reading with its games in the order the partner opened them. A game still open keeps
    /// its place in `previous`, and a new one goes last.
    func ordered(after previous: PartnerPresence?) -> PartnerPresence {
        let kept = previous?.games.filter(games.contains) ?? []
        var ordered = self
        ordered.games = kept + games.filter { !kept.contains($0) }
        return ordered
    }
}

/// One reading of the presence query: this person's own "Show when I'm here", and the partner while
/// they are in the app and both partners show it.
nonisolated struct PartnerPresenceReading: Equatable, Sendable {
    var showsPresence: Bool
    var partner: PartnerPresence?
}

/// What the model knows of the partner during one run.
nonisolated enum PartnerFeed: Equatable, Sendable {
    /// No reading yet in this run, or the subscription dropped, so nobody can say where the partner is.
    case waiting
    /// The latest reading. Nil while the partner is away or either partner hides their presence.
    case reading(PartnerPresence?)

    var partner: PartnerPresence? {
        if case let .reading(partner) = self { partner } else { nil }
    }
}

/// A partner's new message the avatar shows for a moment in place of a banner.
nonisolated struct PresenceMessageNotice: Equatable, Sendable {
    let messageID: UUID
    let chat: ThreadChatSubject
    let preview: String
}

/// Something the partner just did that the avatar says for a moment.
nonisolated enum PresenceNotice: Equatable, Sendable {
    case message(PresenceMessageNotice)
    case openedGame(GameKind)
    /// A notification from the partner that arrived while the app is open, such as a letter or a
    /// story.
    case update(PaeoniaForegroundNotice)

    /// True when the notice tells this person something new. A message must come from a chat they
    /// don't have on screen, and a game must be one they don't have open.
    func concerns(_ viewer: PresenceViewerPlace) -> Bool {
        switch self {
        case let .message(message): message.chat != viewer.visibleChat
        case let .openedGame(kind): kind != viewer.openGame
        case .update: true
        }
    }

    var callout: PresenceCallout {
        switch self {
        case let .message(message): .message(message)
        case let .openedGame(kind): .openedGame(kind)
        case let .update(update): .update(update)
        }
    }
}

/// What this person has on screen, which decides what the avatar leaves out.
nonisolated struct PresenceViewerPlace: Equatable, Sendable {
    var visibleChat: ThreadChatSubject?
    var openGame: GameKind?
}

/// What the avatar calls out in its capsule. A tap opens the chat, the game or the screen it is about.
nonisolated enum PresenceCallout: Equatable, Sendable {
    case message(PresenceMessageNotice)
    case openedGame(GameKind)
    case typing(ThreadChatSubject)
    case update(PaeoniaForegroundNotice)

    var destination: PresenceDestination? {
        switch self {
        case let .message(message): .chat(message.chat)
        case let .openedGame(kind): .game(kind)
        case let .typing(chat): .chat(chat)
        case let .update(update): update.deepLink.map(PresenceDestination.link)
        }
    }
}

/// Where the partner is, shown as the avatar's badge.
nonisolated enum PresencePlace: Equatable, Sendable {
    case playing(GameKind)
    case chatting(ThreadChatSubject)
    case here

    /// A game comes before a chat.
    init(_ partner: PartnerPresence) {
        if let game = partner.game {
            self = .playing(game)
        } else if let chat = partner.chat {
            self = .chatting(chat)
        } else {
            self = .here
        }
    }
}

/// What the avatar says about the partner.
nonisolated struct PresencePillStatus: Equatable, Sendable {
    var callout: PresenceCallout?
    var place: PresencePlace

    /// The callout is the notice, or else the chat the partner types in. The chat this person has
    /// on screen makes no typing callout, and a notice that no longer concerns them makes none.
    init(partner: PartnerPresence, notice: PresenceNotice?, viewer: PresenceViewerPlace) {
        place = PresencePlace(partner)
        if let notice, notice.concerns(viewer) {
            callout = notice.callout
        } else {
            callout = partner.typing.flatMap { $0 == viewer.visibleChat ? nil : .typing($0) }
        }
    }
}

/// Where a tap on the partner's avatar goes. `MainTabView` opens it.
nonisolated enum PresenceDestination: Equatable, Sendable {
    /// "Just us" for Message, or the chat a message or typing is about.
    case chat(ThreadChatSubject)
    /// The game the partner is in, for Join and for "Opened".
    case game(GameKind)
    /// Where the partner's notification goes, as if it were tapped.
    case link(PaeoniaDeepLink)
}
