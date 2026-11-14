import Foundation

/// How this phone has shown one of the app's swipes (`Swipe`), and whether the person has
/// used it. First what the swipe opens peeks in a few times, on different days. Someone who
/// still opens it with its button after that gets one tip in words. Everything stops once
/// they swipe. It is per phone, like the how-to-play cards.
nonisolated struct SwipeLessons: Codable, Equatable {
    static let peekLimit = 3
    /// Opens with the button after the last peek before the tip shows.
    static let buttonOpensBeforeTip = 2

    private(set) var peekCount = 0
    private(set) var lastPeek: Date?
    private(set) var hasSwiped = false
    private(set) var buttonOpensAfterPeeks = 0
    /// The tip shows when what the button opened next closes, on a screen the swipe works on.
    private(set) var tipIsDue = false
    private(set) var tipShown = false

    /// A screen shown at `date` shows the peek. At most one a day, so the peeks are spread
    /// over the first days of use.
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

extension SwipeLessons {
    /// The swipes the app teaches, each with its own lessons, saved under its key.
    enum Swipe: String {
        /// Up on a game screen, for the game's chat.
        case gameChat = "paeonia.games.chatSwipeLessons.v1"
        /// In from the right edge of the screen, for Just us.
        case justUs = "paeonia.chats.justUsSwipeLessons.v1"
    }

    /// This phone's lessons for `swipe`. A change is saved at once.
    static subscript(swipe: Swipe) -> SwipeLessons {
        get {
            UserDefaults.standard.data(forKey: swipe.rawValue)
                .flatMap { try? JSONDecoder().decode(SwipeLessons.self, from: $0) } ?? SwipeLessons()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: swipe.rawValue) }
    }
}
