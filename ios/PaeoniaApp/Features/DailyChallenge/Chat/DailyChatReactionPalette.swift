import Foundation
import Observation

/// The emoji the reaction row offers, like Tidex's: the ones this person picked most
/// recently first, filled up with the usual ones. The list stays on this phone and
/// sign-out clears it.
@MainActor
@Observable
final class DailyChatReactionPalette {
    static let shared = DailyChatReactionPalette()

    private static let defaults = ["❤️", "😂", "🥰", "😮", "😢", "👍"]
    private static let maxVisible = 6
    private static let maxRecents = 12
    private static let recentsKey = "dailyChat.reaction.recents"

    /// The emoji the row shows, in order.
    private(set) var emojis: [String] = DailyChatReactionPalette.defaults

    private let userDefaults: UserDefaults
    @ObservationIgnored private var recents: [String] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        recents = (userDefaults.stringArray(forKey: Self.recentsKey) ?? []).compactMap(Self.normalized)
        rebuild()
    }

    /// Moves the picked emoji to the front.
    func recordSelection(_ emoji: String) {
        guard let emoji = Self.normalized(emoji) else { return }
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        userDefaults.set(recents, forKey: Self.recentsKey)
        rebuild()
    }

    /// Forgets the recent picks, for sign-out.
    func clearAll() {
        recents = []
        userDefaults.removeObject(forKey: Self.recentsKey)
        rebuild()
    }

    private func rebuild() {
        let recent = Array(recents.prefix(Self.maxVisible))
        emojis = Array((recent + Self.defaults.filter { !recent.contains($0) }).prefix(Self.maxVisible))
    }

    /// The first character, when it is an emoji. Digits and letters are refused.
    private nonisolated static func normalized(_ value: String) -> String? {
        guard let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        let scalars = first.unicodeScalars
        let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.count > 1 && scalars.first?.properties.isEmoji == true)
        return isEmoji ? String(first) : nil
    }
}
