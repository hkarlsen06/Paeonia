import Foundation

/// The first rule a typed word breaks. The server checks the same rules again.
nonisolated enum MindMeldWordIssue: Equatable, Sendable {
    case tooLong
    case tooManyWords
    case noLetters
    /// A character other than letters, marks, numbers, spaces, hyphens and apostrophes.
    case badCharacters
    /// The same word, by match key, was already said in this game. Holds the
    /// earlier word as it was said.
    case repeatOf(String)
}

/// The rules for a Mind Meld word: what is allowed, and the match key the
/// server compares. `matchKey` must give the same result as the server's.
nonisolated enum MindMeldWord {
    static let maxLength = 30
    static let maxWords = 3

    /// The word trimmed, with single spaces between words and the typed case kept.
    static func normalized(_ text: String) -> String {
        DrawAndGuessAnswer.collapsingWhitespace(text)
    }

    /// The first rule the word breaks, or nil when it is fine. An empty field
    /// also gives nil, and the caller does not let it lock in.
    /// `used` maps the match key of each word said in this game's revealed
    /// rounds to that word as it was said (`RemoteMindMeldGame.usedWords`).
    static func validate(_ text: String, used: [String: String]) -> MindMeldWordIssue? {
        let word = normalized(text)
        guard !word.isEmpty else { return nil }
        // Code points, as the server counts them.
        if word.unicodeScalars.count > maxLength {
            return .tooLong
        }
        if word.split(separator: " ").count > maxWords {
            return .tooManyWords
        }
        if !word.unicodeScalars.allSatisfy(isAllowed) {
            return .badCharacters
        }
        // A few letters, such as the Greek ypogegrammeni, are accents once
        // normalized and leave an empty key, as on the server.
        if !word.unicodeScalars.contains(where: isLetter) || matchKey(word).isEmpty {
            return .noLetters
        }
        return used[matchKey(word)].map(MindMeldWordIssue.repeatOf)
    }

    /// What the server compares (`matchKey` in `backend/convex/lib/mindMeld.ts`,
    /// in the same order): Unicode NFKC, lowercase and NFD, then æ, ø and the
    /// letters a and o with a ring or diaeresis behind them spelled out, then
    /// accents removed and only letters and numbers kept. "Ice cream",
    /// "ice-cream" and "icecream" share a key, and so do "Blåbær" and "blaabaer".
    static func matchKey(_ text: String) -> String {
        let lowered = text.precomposedStringWithCompatibilityMapping.lowercased()
        let scalars = Array(lowered.decomposedStringWithCanonicalMapping.unicodeScalars)
        var key = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() where !isMark(scalar) {
            let marks = scalars[(index + 1)...].prefix(while: isMark)
            switch scalar {
            case "æ": key.append(contentsOf: "ae".unicodeScalars)
            case "ø": key.append(contentsOf: "oe".unicodeScalars)
            case "a" where marks.contains("\u{030A}"): key.append(contentsOf: "aa".unicodeScalars)
            case "a" where marks.contains("\u{0308}"): key.append(contentsOf: "ae".unicodeScalars)
            case "o" where marks.contains("\u{0308}"): key.append(contentsOf: "oe".unicodeScalars)
            default:
                if isLetter(scalar) || isNumber(scalar) { key.append(scalar) }
            }
        }
        return String(key)
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    private static func isNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: true
        default: false
        }
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        isLetter(scalar) || isMark(scalar) || isNumber(scalar)
            || scalar == " " || scalar == "-" || scalar == "'" || scalar == "\u{2019}"
    }
}

nonisolated extension RemoteMindMeldGame {
    /// Every word said in the revealed rounds, by both partners, keyed by match
    /// key. A key holds the first word said with it.
    var usedWords: [String: String] {
        var used: [String: String] = [:]
        for round in rounds where round.state == .revealed {
            for word in [round.myWord, round.partnerWord].compactMap(\.self) {
                let key = MindMeldWord.matchKey(word)
                if !key.isEmpty, used[key] == nil {
                    used[key] = word
                }
            }
        }
        return used
    }
}
