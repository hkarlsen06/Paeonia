import SwiftUI

/// Where the partner is while they have Paeonia open, decoded from `appPresence:get_partner_presence`
/// at the boundary.
nonisolated struct PartnerPresence: Equatable, Sendable {
    /// The game screens the partner has open, the one they opened last at the end.
    var games: [GameKind] = []
    /// The partner has the couple's widget drawing open.
    var isDrawing = false
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

/// The call that covers the partner's avatar, which decides what the call says in its place.
nonisolated enum PresenceCallCover: Equatable, Sendable {
    case none
    /// The ring pill or the call's bubble. They say which game or drawing the partner opened, and the
    /// partner's messages and notifications keep their banners around them.
    case small
    /// The full call screen, which hides the banners, so it says the partner's messages and
    /// notifications as well.
    case fullScreen
}

/// Something the partner just did that the avatar says for a moment.
nonisolated enum PresenceNotice: Equatable, Sendable {
    case message(PresenceMessageNotice)
    case openedGame(GameKind)
    case openedDrawing
    /// A notification from the partner that arrived while the app is open, such as a letter or a
    /// story.
    case update(PaeoniaForegroundNotice)
    /// A game newly needs this person. Only the full call screen says it, because it covers the game.
    case game(GameKind, GameNeed)

    /// True when the notice tells this person something new. A message must come from a chat they
    /// don't have on screen, and a game the partner opened must be one they don't have open.
    func concerns(_ viewer: PresenceViewerPlace) -> Bool {
        switch self {
        case let .message(message): message.chat != viewer.visibleChat
        case let .openedGame(kind): kind != viewer.openGame
        case .openedDrawing: !viewer.isDrawing
        case .update, .game: true
        }
    }

    /// False once the partner has left the game or the drawing the notice says they opened.
    func isTrue(of partner: PartnerPresence?) -> Bool {
        switch self {
        case let .openedGame(kind): partner?.games.contains(kind) == true
        case .openedDrawing: partner?.isDrawing == true
        case .message, .update, .game: true
        }
    }

    /// False for a game that needs this person. That is the game's news, so it stays when the
    /// partner leaves or hides their presence, and goes when the call no longer covers the game.
    var isAboutPartner: Bool {
        if case .game = self { false } else { true }
    }

    var callout: PresenceCallout {
        switch self {
        case let .message(message): .message(message)
        case let .openedGame(kind): .openedGame(kind)
        case .openedDrawing: .openedDrawing
        case let .update(update): .update(update)
        case let .game(kind, need): .game(kind, need)
        }
    }
}

/// What this person has on screen, which decides what the avatar leaves out.
nonisolated struct PresenceViewerPlace: Equatable, Sendable {
    var visibleChat: ThreadChatSubject?
    var openGame: GameKind?
    /// The chat of the game on screen. Nil outside a game.
    var gameChat: GameChatSubject?
    /// The couple's widget drawing is open on the Us tab.
    var isDrawing = false

    /// Where the avatar's Message button goes while no chat waits unread. In a game it opens that
    /// game's chat, whose swipe up is easy to miss, and "Just us" once that chat is open. Elsewhere
    /// it opens "Just us".
    var messageChat: ThreadChatSubject {
        if let gameChat, visibleChat != .game(gameChat) { return .game(gameChat) }
        return .couple
    }
}

/// What the avatar calls out in its capsule. A tap opens the chat, the game or the screen it is about.
nonisolated enum PresenceCallout: Equatable, Sendable {
    case message(PresenceMessageNotice)
    case openedGame(GameKind)
    case openedDrawing
    case typing(ThreadChatSubject)
    case update(PaeoniaForegroundNotice)
    case game(GameKind, GameNeed)

    var destination: PresenceDestination? {
        switch self {
        case let .message(message): .chat(message.chat)
        case let .openedGame(kind), let .game(kind, _): .game(kind)
        case .openedDrawing: .drawing
        case let .typing(chat): .chat(chat)
        case let .update(update): update.deepLink.map(PresenceDestination.link)
        }
    }
}

/// Where the partner is, shown as the avatar's badge.
nonisolated enum PresencePlace: Equatable, Sendable {
    case playing(GameKind)
    case drawing
    case chatting(ThreadChatSubject)
    case here

    /// A game comes before the drawing, and the drawing before a chat.
    init(_ partner: PartnerPresence) {
        if let game = partner.game {
            self = .playing(game)
        } else if partner.isDrawing {
            self = .drawing
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
    /// The couple's widget drawing, while the partner draws.
    case drawing
    /// Where the partner's notification goes, as if it were tapped.
    case link(PaeoniaDeepLink)
}
