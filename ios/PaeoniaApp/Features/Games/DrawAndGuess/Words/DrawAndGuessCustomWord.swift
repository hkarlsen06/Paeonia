import Foundation

/// The "Draw your own" word: 2 to 20 letters, at most three words, and only
/// the letters A to Z plus Æ, Ø and Å.
nonisolated enum DrawAndGuessCustomWord {
    static let letterRange = 2...20
    static let maxWords = 3

    enum Failure: Error, Equatable, Sendable {
        case tooShort
        case tooLong
        case tooManyWords
        case notAllowedCharacter
    }

    /// The word trimmed, with single spaces between words and the typed case
    /// kept, or the first rule it breaks.
    static func validate(_ text: String) -> Result<String, Failure> {
        // Joins a letter typed as a base letter plus a combining mark (å).
        let word = DrawAndGuessAnswer.collapsingWhitespace(text.precomposedStringWithCanonicalMapping)
        guard word.unicodeScalars.allSatisfy({ $0 == " " || isAllowedLetter($0) }) else {
            return .failure(.notAllowedCharacter)
        }
        let letterCount = word.count { $0 != " " }
        if letterCount < letterRange.lowerBound {
            return .failure(.tooShort)
        }
        if letterCount > letterRange.upperBound {
            return .failure(.tooLong)
        }
        if word.split(separator: " ").count > maxWords {
            return .failure(.tooManyWords)
        }
        return .success(word)
    }

    private static func isAllowedLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "æ", "ø", "å", "Æ", "Ø", "Å":
            true
        default:
            false
        }
    }
}
