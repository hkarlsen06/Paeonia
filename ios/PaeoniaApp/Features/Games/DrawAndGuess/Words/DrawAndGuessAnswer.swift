import Foundation

/// How an answer is read everywhere in the game: tiles, slots, and guess checks.
nonisolated enum DrawAndGuessAnswer {
    /// Trims the text and replaces every run of whitespace with one space.
    static func collapsingWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The answer in capitals with single spaces between words.
    static func normalized(_ answer: String) -> String {
        collapsingWhitespace(answer).uppercased()
    }

    /// The capital letters of the answer, without spaces.
    static func letters(of answer: String) -> [Character] {
        normalized(answer).filter { $0 != " " }
    }

    /// Each character of the normalized answer with its place among the letters,
    /// or nil for a space. The reveal lights letters by that place, so a space
    /// must not take a number.
    static func numberedCharacters(of answer: String) -> [(character: Character, letter: Int?)] {
        var next = 0
        return normalized(answer).map { character in
            guard character != " " else { return (character, nil) }
            defer { next += 1 }
            return (character, next)
        }
    }

    /// A word as the screens show it: the first letter in capitals, the rest as typed.
    static func display(_ word: String) -> String {
        let text = collapsingWhitespace(word)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
