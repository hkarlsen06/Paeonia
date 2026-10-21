import Foundation

/// What the signed-in person calls their partner, and the only place that decides it.
///
/// A person can give their partner a nickname, such as "Babe" or "Ellie 🌸". The app shows the
/// nickname wherever it would show the partner's name. Without one, it shows the name the partner
/// chose for themselves. The nickname is private to the person who set it, and the server keeps it.
///
/// Views and view models take the resolved name (`display`, or `displayOrFallback` for copy that
/// must read as text) from `AccessRouteResolution.partnerName` and pass it down. They never read
/// `accountName`, because that is the partner's own name and shows through a nickname. SwiftLint's
/// `partner_account_name_read` rule flags it outside this file and the nickname editor.
nonisolated struct PartnerName: Equatable, Hashable, Sendable {
    /// The longest nickname, counted in Unicode scalars so it matches the server's code point count.
    static let maxNicknameLength = 30

    /// The name the partner chose for themselves.
    let accountName: String?
    /// The nickname this person gave their partner, if any.
    let nickname: String?

    init(accountName: String?, nickname: String?) {
        self.accountName = accountName?.trimmedNonEmpty
        self.nickname = nickname?.trimmedNonEmpty
    }

    /// The name to show: the nickname, otherwise the partner's own name. Nil when neither is known.
    var display: String? {
        nickname ?? accountName
    }

    /// `display`, or "Your partner" when no name is known yet. Use it where the copy needs text.
    var displayOrFallback: String {
        display ?? String(localized: .pairingCelebrationPartnerName)
    }

    /// The nickname to send, or nil to clear it: trimmed, with every run of whitespace turned into
    /// one space. This matches what the server stores.
    static func normalizedNickname(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// True when the server accepts `nickname` (already normalized).
    static func isValidNickname(_ nickname: String) -> Bool {
        nickname.unicodeScalars.count <= maxNicknameLength
            && !nickname.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}
