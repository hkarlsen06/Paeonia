import Foundation

/// A display name is one or two words, so a double name like "Anne Marie" fits
/// but a first name with a surname does not.
nonisolated enum AuthDisplayNamePolicy {
    static let maxWordCount = 2

    /// The name to pre-fill from a sign-in provider's first name. Words past the
    /// second are dropped.
    static func normalizedFirstName(from value: String) -> String? {
        joined(value.split(whereSeparator: \.isWhitespace).prefix(maxWordCount))
    }

    /// The typed name with its spaces tidied, or nil when it is empty or longer
    /// than two words.
    static func validatedName(from value: String) -> String? {
        let words = value.split(whereSeparator: \.isWhitespace)
        guard words.count <= maxWordCount else {
            return nil
        }

        return joined(words[...])
    }

    private static func joined(_ words: ArraySlice<Substring>) -> String? {
        guard !words.isEmpty else {
            return nil
        }

        return String(words.joined(separator: " ").prefix(80))
    }
}
