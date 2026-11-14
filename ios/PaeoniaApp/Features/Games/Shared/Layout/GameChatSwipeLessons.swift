import Foundation

/// How this phone has shown the swipe up that opens a game's chat, and whether the person
/// has used it. First the chat peeks up from under a game screen a few times, on different
/// days. Someone who still opens the chat with its button after that gets one tip in words.
/// Everything stops once they swipe. It is per phone, like the how-to-play cards.
nonisolated struct GameChatSwipeLessons: Codable, Equatable {
    static let peekLimit = 3
    /// Chats opened with the button after the last peek before the tip shows.
    static let buttonOpensBeforeTip = 2

    private(set) var peekCount = 0
    private(set) var lastPeek: Date?
    private(set) var hasSwiped = false
    private(set) var buttonOpensAfterPeeks = 0
    /// The tip shows when the chat panel next closes, over the game the swipe works on.
    private(set) var tipIsDue = false
    private(set) var tipShown = false

    /// A game screen opened at `date` shows the peek. At most one a day, so the peeks are
    /// spread over the first days of play.
    func peekIsDue(at date: Date, calendar: Calendar) -> Bool {
        guard !hasSwiped, peekCount < Self.peekLimit else { return false }
        return lastPeek.map { !calendar.isDate($0, inSameDayAs: date) } ?? true
    }

    mutating func peeked(at date: Date) {
        peekCount += 1
        lastPeek = date
    }

    mutating func swiped() {
        hasSwiped = true
        tipIsDue = false
    }

    mutating func openedWithButton() {
        guard !hasSwiped, !tipShown, peekCount >= Self.peekLimit else { return }
        buttonOpensAfterPeeks += 1
        tipIsDue = buttonOpensAfterPeeks >= Self.buttonOpensBeforeTip
    }

    /// True once, when the tip should show now.
    mutating func takeTip() -> Bool {
        guard tipIsDue else { return false }
        tipIsDue = false
        tipShown = true
        return true
    }
}

extension GameChatSwipeLessons {
    private static let key = "paeonia.games.chatSwipeLessons.v1"

    /// This phone's lessons. A change is saved at once.
    static var saved: GameChatSwipeLessons {
        get {
            UserDefaults.standard.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(GameChatSwipeLessons.self, from: $0) } ?? GameChatSwipeLessons()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}
